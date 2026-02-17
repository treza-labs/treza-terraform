import socket,json,struct,sys,os,time,threading,subprocess,logging
try:
    import boto3
except ImportError:
    boto3=None
import urllib.request,urllib.error

VMADDR_CID_ANY=0xFFFFFFFF
VSOCK_PORT=5000
logging.basicConfig(level=logging.INFO,format="%(asctime)s [PARENT] %(levelname)s %(message)s",datefmt="%Y-%m-%d %H:%M:%S")
log=logging.getLogger("parent-proxy")

class CloudWatchLogger:
    def __init__(self,enclave_id,region=None):
        self.enclave_id=enclave_id
        self.region=region or os.environ.get("AWS_DEFAULT_REGION","us-west-2")
        self.client=None
        self.log_group=f"/aws/ec2/enclave/{enclave_id}"
        self.log_streams={}
        self._lock=threading.Lock()
        if boto3:
            try:
                self.client=boto3.client("logs",region_name=self.region)
                self._ensure_log_group()
            except Exception as e:
                log.warning(f"CloudWatch init failed: {e}")
    def _ensure_log_group(self):
        try:self.client.create_log_group(logGroupName=self.log_group)
        except:pass
    def _ensure_log_stream(self,stream_name):
        if stream_name not in self.log_streams:
            try:self.client.create_log_stream(logGroupName=self.log_group,logStreamName=stream_name)
            except:pass
            self.log_streams[stream_name]=True
    def write(self,stream_name,message):
        log.info(f"[{stream_name}] {message}")
        if not self.client:return
        with self._lock:
            try:
                self._ensure_log_stream(stream_name)
                resp=self.client.describe_log_streams(logGroupName=self.log_group,logStreamNamePrefix=stream_name)
                kwargs={"logGroupName":self.log_group,"logStreamName":stream_name,"logEvents":[{"timestamp":int(time.time()*1000),"message":message}]}
                if resp["logStreams"]:
                    token=resp["logStreams"][0].get("uploadSequenceToken")
                    if token:kwargs["sequenceToken"]=token
                self.client.put_log_events(**kwargs)
            except Exception as e:
                log.warning(f"CloudWatch write error: {e}")

def send_message(conn,message):
    payload=json.dumps(message).encode("utf-8")
    header=struct.pack("!I",len(payload))
    conn.sendall(header+payload)

def recv_message(conn):
    header=_recv_exact(conn,4)
    if not header:return None
    length=struct.unpack("!I",header)[0]
    if length>10*1024*1024:raise ValueError(f"Message too large: {length}")
    payload=_recv_exact(conn,length)
    if not payload:return None
    return json.loads(payload.decode("utf-8"))

def _recv_exact(conn,n):
    data=b""
    while len(data)<n:
        chunk=conn.recv(n-len(data))
        if not chunk:return None
        data+=chunk
    return data

def get_pcr_values():
    try:
        result=subprocess.run(["/usr/bin/nitro-cli","describe-enclaves"],capture_output=True,text=True,timeout=30)
        if result.returncode==0 and result.stdout.strip():
            enclave_data=json.loads(result.stdout)
            if enclave_data and len(enclave_data)>0:
                m=enclave_data[0].get("Measurements",{})
                return {"PCR0":m.get("PCR0","unavailable"),"PCR1":m.get("PCR1","unavailable"),"PCR2":m.get("PCR2","unavailable")}
    except subprocess.TimeoutExpired:
        log.warning("Timeout getting PCRs")
    except Exception as e:
        log.warning(f"Error getting PCRs: {e}")
    return {"PCR0":"ERROR_NSM_UNAVAILABLE","PCR1":"ERROR_NSM_UNAVAILABLE","PCR2":"ERROR_NSM_UNAVAILABLE"}

def handle_http_request(payload):
    method=payload.get("method","GET")
    url=payload.get("url","")
    headers=payload.get("headers",{})
    body=payload.get("body","")
    try:
        req=urllib.request.Request(url,data=body.encode("utf-8") if body else None,headers=headers,method=method)
        with urllib.request.urlopen(req,timeout=55) as response:
            return {"status":response.status,"headers":dict(response.getheaders()),"body":response.read().decode("utf-8",errors="replace")}
    except urllib.error.HTTPError as e:
        return {"status":e.code,"headers":dict(e.headers) if e.headers else {},"body":e.read().decode("utf-8",errors="replace") if e.fp else ""}
    except urllib.error.URLError as e:
        return {"status":502,"headers":{},"body":f"Network error: {e.reason}"}
    except Exception as e:
        return {"status":502,"headers":{},"body":f"Proxy error: {e}"}

def handle_kms_request(payload):
    if not boto3:return {"error":"boto3 not available"}
    operation=payload.get("operation","")
    data=payload.get("data",{})
    try:
        kms=boto3.client("kms",region_name=os.environ.get("AWS_DEFAULT_REGION","us-west-2"))
        if operation=="decrypt":
            r=kms.decrypt(CiphertextBlob=bytes.fromhex(data.get("ciphertext","")),KeyId=data.get("key_id",""))
            return {"result":{"plaintext":r["Plaintext"].hex(),"key_id":r["KeyId"]}}
        elif operation=="generate-data-key":
            r=kms.generate_data_key(KeyId=data.get("key_id",""),KeySpec=data.get("key_spec","AES_256"))
            return {"result":{"plaintext":r["Plaintext"].hex(),"ciphertext_blob":r["CiphertextBlob"].hex(),"key_id":r["KeyId"]}}
        elif operation=="encrypt":
            r=kms.encrypt(KeyId=data.get("key_id",""),Plaintext=bytes.fromhex(data.get("plaintext","")))
            return {"result":{"ciphertext_blob":r["CiphertextBlob"].hex(),"key_id":r["KeyId"]}}
        else:
            return {"error":f"Unsupported KMS operation: {operation}"}
    except Exception as e:
        return {"error":f"KMS error: {e}"}

def handle_connection(conn,addr,cw):
    cw.write("system",f"Enclave connected from CID {addr}")
    try:
        while True:
            msg=recv_message(conn)
            if msg is None:break
            t=msg.get("type","")
            mid=msg.get("id","")
            p=msg.get("payload",{})
            if t=="handshake":
                cw.write("system",f"Handshake: enclave={p.get('enclave_id')}, proto={p.get('protocol_version')}, caps={p.get('capabilities')}")
                send_message(conn,{"type":"handshake_ack","id":mid,"payload":{"status":"ok","parent_version":"2.0"}})
            elif t=="log":
                level=p.get("level","info")
                message=p.get("message","")
                stream="application" if level.startswith("app") else "system"
                cw.write(stream,f"[{level.upper()}] {message}")
            elif t=="http_request":
                result=handle_http_request(p)
                send_message(conn,{"type":"http_response","id":mid,"payload":result})
            elif t=="kms_request":
                result=handle_kms_request(p)
                send_message(conn,{"type":"kms_response","id":mid,"payload":result})
            elif t=="pcr_request":
                pcrs=get_pcr_values()
                cw.write("system",f"PCR values: {json.dumps(pcrs)}")
                send_message(conn,{"type":"pcr_response","id":mid,"payload":{"pcr_values":pcrs}})
            elif t=="health_report":
                status=p.get("status","unknown")
                ec=p.get("exit_code")
                wt=p.get("workload_type","unknown")
                msg_text=f"Health: status={status}, workload={wt}"
                if ec is not None:msg_text+=f", exit_code={ec}"
                cw.write("health",msg_text)
            else:
                cw.write("system",f"Unknown message type: {t}")
                send_message(conn,{"type":"error","id":mid,"payload":{"error":f"Unknown: {t}"}})
    except Exception as e:
        cw.write("errors",f"Connection error: {e}")
    finally:
        conn.close()
        cw.write("system","Connection closed")

def main():
    enclave_id=sys.argv[1]
    cw=CloudWatchLogger(enclave_id)
    cw.write("system",f"Parent proxy v2.0 started for {enclave_id}")
    try:
        sock=socket.socket(socket.AF_VSOCK,socket.SOCK_STREAM)
        sock.bind((VMADDR_CID_ANY,VSOCK_PORT))
        sock.listen(5)
        cw.write("system",f"Listening on vsock port {VSOCK_PORT}")
        while True:
            conn,addr=sock.accept()
            cw.write("system",f"Connection accepted from {addr}")
            threading.Thread(target=handle_connection,args=(conn,addr,cw),daemon=True).start()
    except Exception as e:
        cw.write("errors",f"Parent proxy failed: {e}")
        sys.exit(1)

if __name__=="__main__":main()
