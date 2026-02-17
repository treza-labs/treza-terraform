import socket,json,struct,sys,os,time,signal,subprocess,threading
from http.server import HTTPServer,BaseHTTPRequestHandler
from urllib.parse import urlparse

VMADDR_CID_HOST=3
VSOCK_PORT=5000
HTTP_PROXY_PORT=3128
KMS_PROXY_PORT=8000
HEALTH_CHECK_PORT=8888

_vsock_lock=threading.Lock()
_vsock_conn=None
_request_id_counter=0
_pending_responses={}
_pending_lock=threading.Lock()
_shutdown_event=threading.Event()

def next_request_id():
    global _request_id_counter
    with _vsock_lock:
        _request_id_counter+=1
        return f"req-{_request_id_counter}"

def send_message(sock,message):
    payload=json.dumps(message).encode("utf-8")
    header=struct.pack("!I",len(payload))
    with _vsock_lock:
        sock.sendall(header+payload)

def recv_message(sock):
    header=_recv_exact(sock,4)
    if not header:return None
    length=struct.unpack("!I",header)[0]
    if length>10*1024*1024:raise ValueError(f"Message too large: {length}")
    payload=_recv_exact(sock,length)
    if not payload:return None
    return json.loads(payload.decode("utf-8"))

def _recv_exact(sock,n):
    data=b""
    while len(data)<n:
        chunk=sock.recv(n-len(data))
        if not chunk:return None
        data+=chunk
    return data

def send_log(level,message):
    global _vsock_conn
    if _vsock_conn:
        try:
            send_message(_vsock_conn,{"type":"log","id":next_request_id(),"payload":{"level":level,"message":message,"timestamp":time.time()}})
        except:pass
    print(f"[ENCLAVE-PROXY] [{level.upper()}] {message}",flush=True)

def send_request_and_wait(msg_type,payload,timeout=30):
    global _vsock_conn
    req_id=next_request_id()
    event=threading.Event()
    with _pending_lock:
        _pending_responses[req_id]={"event":event,"response":None}
    send_message(_vsock_conn,{"type":msg_type,"id":req_id,"payload":payload})
    if not event.wait(timeout=timeout):
        with _pending_lock:_pending_responses.pop(req_id,None)
        raise TimeoutError(f"Request {req_id} timed out")
    with _pending_lock:
        result=_pending_responses.pop(req_id)
    return result["response"]

def response_dispatcher():
    global _vsock_conn
    while not _shutdown_event.is_set():
        try:
            msg=recv_message(_vsock_conn)
            if msg is None:
                send_log("error","Parent connection lost")
                _shutdown_event.set()
                break
            req_id=msg.get("id")
            if req_id:
                with _pending_lock:
                    if req_id in _pending_responses:
                        _pending_responses[req_id]["response"]=msg
                        _pending_responses[req_id]["event"].set()
        except Exception as e:
            if not _shutdown_event.is_set():
                send_log("error",f"Dispatcher error: {e}")
                time.sleep(1)

class HTTPProxyHandler(BaseHTTPRequestHandler):
    def do_GET(self):self._proxy("GET")
    def do_POST(self):self._proxy("POST")
    def do_PUT(self):self._proxy("PUT")
    def do_DELETE(self):self._proxy("DELETE")
    def do_PATCH(self):self._proxy("PATCH")
    def do_HEAD(self):self._proxy("HEAD")
    def do_OPTIONS(self):self._proxy("OPTIONS")
    def _proxy(self,method):
        try:
            cl=int(self.headers.get("Content-Length",0))
            body=self.rfile.read(cl) if cl>0 else b""
            hdrs={k:v for k,v in self.headers.items() if k.lower() not in ("host","proxy-connection","proxy-authorization")}
            resp=send_request_and_wait("http_request",{"method":method,"url":self.path,"headers":hdrs,"body":body.decode("utf-8",errors="replace") if body else ""},timeout=60)
            rp=resp.get("payload",{})
            status=rp.get("status",502)
            rh=rp.get("headers",{})
            rb=rp.get("body","").encode("utf-8")
            self.send_response(status)
            for k,v in rh.items():
                if k.lower() not in ("transfer-encoding","content-length"):self.send_header(k,v)
            self.send_header("Content-Length",str(len(rb)))
            self.end_headers()
            self.wfile.write(rb)
        except TimeoutError:self.send_error(504,"Gateway Timeout")
        except Exception as e:self.send_error(502,f"Bad Gateway: {e}")
    def log_message(self,fmt,*args):pass

class KMSProxyHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        try:
            cl=int(self.headers.get("Content-Length",0))
            body=self.rfile.read(cl) if cl>0 else b""
            data=json.loads(body.decode("utf-8")) if body else {}
            op=urlparse(self.path).path.strip("/")
            resp=send_request_and_wait("kms_request",{"operation":op,"data":data},timeout=30)
            rp=resp.get("payload",{})
            if rp.get("error"):
                self.send_response(400)
                rb=json.dumps({"error":rp["error"]}).encode("utf-8")
            else:
                self.send_response(200)
                rb=json.dumps(rp.get("result",{})).encode("utf-8")
            self.send_header("Content-Type","application/json")
            self.send_header("Content-Length",str(len(rb)))
            self.end_headers()
            self.wfile.write(rb)
        except Exception as e:self.send_error(500,f"KMS error: {e}")
    def log_message(self,fmt,*args):pass

class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        body=json.dumps({"status":"healthy","proxy":"running","vsock":"connected" if _vsock_conn else "disconnected"}).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type","application/json")
        self.send_header("Content-Length",str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self,fmt,*args):pass

def run_server(port,handler):
    srv=HTTPServer(("127.0.0.1",port),handler)
    srv.timeout=1
    while not _shutdown_event.is_set():srv.handle_request()
    srv.server_close()

def stream_output(proc,name):
    stream=proc.stdout if name=="stdout" else proc.stderr
    if not stream:return
    for line in iter(stream.readline,b""):
        if _shutdown_event.is_set():break
        decoded=line.decode("utf-8",errors="replace").rstrip("\n")
        if decoded:send_log("app" if name=="stdout" else "app_err",decoded)

def connect_to_parent(max_retries=30,retry_delay=10):
    global _vsock_conn
    print("[ENCLAVE-PROXY] Waiting for parent proxy...",flush=True)
    time.sleep(5)
    for attempt in range(1,max_retries+1):
        try:
            sock=socket.socket(socket.AF_VSOCK,socket.SOCK_STREAM)
            sock.settimeout(120)
            sock.connect((VMADDR_CID_HOST,VSOCK_PORT))
            _vsock_conn=sock
            send_message(sock,{"type":"handshake","id":next_request_id(),"payload":{"enclave_id":os.environ.get("ENCLAVE_ID","unknown"),"protocol_version":"2.0","capabilities":["http_proxy","kms_proxy","log_stream","health"]}})
            print(f"[ENCLAVE-PROXY] Connected on attempt {attempt}",flush=True)
            return True
        except Exception as e:
            print(f"[ENCLAVE-PROXY] Attempt {attempt}/{max_retries} failed: {e}",flush=True)
            if attempt<max_retries:time.sleep(retry_delay)
    return False

def main():
    eid=os.environ.get("ENCLAVE_ID","unknown")
    wtype=os.environ.get("TREZA_WORKLOAD_TYPE","batch")
    print(f"[ENCLAVE-PROXY] Starting for {eid} (workload: {wtype})",flush=True)
    if not connect_to_parent():
        print("[ENCLAVE-PROXY] FATAL: Could not connect to parent",flush=True)
        sys.exit(1)
    threading.Thread(target=response_dispatcher,daemon=True).start()
    send_log("info",f"Enclave proxy started for {eid}")

    try:
        resp=send_request_and_wait("pcr_request",{},timeout=30)
        pcrs=resp.get("payload",{}).get("pcr_values",{})
        send_log("info",f"PCR0: {pcrs.get('PCR0','N/A')}")
    except:pass

    for port,handler in [(HTTP_PROXY_PORT,HTTPProxyHandler),(KMS_PROXY_PORT,KMSProxyHandler),(HEALTH_CHECK_PORT,HealthHandler)]:
        threading.Thread(target=run_server,args=(port,handler),daemon=True).start()
    time.sleep(1)

    user_cmd=os.environ.get("TREZA_USER_CMD","")
    if not user_cmd:
        ep=os.environ.get("TREZA_USER_ENTRYPOINT","")
        ca=os.environ.get("TREZA_USER_CMD_ARGS","")
        if ep and ca:user_cmd=f"{ep} {ca}"
        elif ep:user_cmd=ep
        elif ca:user_cmd=ca

    user_proc=None
    if user_cmd:
        env=os.environ.copy()
        env["HTTP_PROXY"]=f"http://127.0.0.1:{HTTP_PROXY_PORT}"
        env["HTTPS_PROXY"]=f"http://127.0.0.1:{HTTP_PROXY_PORT}"
        env["http_proxy"]=f"http://127.0.0.1:{HTTP_PROXY_PORT}"
        env["https_proxy"]=f"http://127.0.0.1:{HTTP_PROXY_PORT}"
        env["TREZA_KMS_ENDPOINT"]=f"http://127.0.0.1:{KMS_PROXY_PORT}"
        env["NO_PROXY"]="127.0.0.1,localhost"
        env["no_proxy"]="127.0.0.1,localhost"
        send_log("info",f"Starting user application: {user_cmd}")
        user_proc=subprocess.Popen(user_cmd,shell=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env)
        threading.Thread(target=stream_output,args=(user_proc,"stdout"),daemon=True).start()
        threading.Thread(target=stream_output,args=(user_proc,"stderr"),daemon=True).start()
    else:
        send_log("warn","No user command configured; running in standalone mode")

    def on_signal(signum,frame):
        send_log("info",f"Signal {signum}, shutting down...")
        _shutdown_event.set()
        if user_proc and user_proc.poll() is None:user_proc.terminate()
    signal.signal(signal.SIGTERM,on_signal)
    signal.signal(signal.SIGINT,on_signal)

    if user_proc:
        if wtype=="batch":
            ec=user_proc.wait()
            send_log("info",f"Application exited with code {ec}")
            send_message(_vsock_conn,{"type":"health_report","id":next_request_id(),"payload":{"status":"completed","exit_code":ec,"workload_type":wtype}})
            time.sleep(5)
            _shutdown_event.set()
        elif wtype in ("service","daemon"):
            hi=int(os.environ.get("TREZA_HEALTH_INTERVAL","30"))
            while not _shutdown_event.is_set():
                if user_proc.poll() is not None:
                    ec=user_proc.returncode
                    send_log("error",f"Service exited unexpectedly with code {ec}")
                    send_message(_vsock_conn,{"type":"health_report","id":next_request_id(),"payload":{"status":"crashed","exit_code":ec,"workload_type":wtype}})
                    break
                try:send_message(_vsock_conn,{"type":"health_report","id":next_request_id(),"payload":{"status":"running","workload_type":wtype}})
                except:pass
                _shutdown_event.wait(timeout=hi)
    else:
        while not _shutdown_event.is_set():_shutdown_event.wait(timeout=30)
    send_log("info","Enclave proxy shutting down")

if __name__=="__main__":main()
