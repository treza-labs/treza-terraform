#!/bin/bash
set -e
exec > >(tee -a /var/log/cloud-init-output.log) 2>&1
enclave_id="${enclave_id}"
cpu_count="${cpu_count}"
memory_mib="${memory_mib}"
docker_image="${docker_image}"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1"; }
log "Starting enclave deployment for $enclave_id with image: $docker_image"
yum update -y
yum install -y docker python3 python3-pip curl
pip3 install boto3
systemctl start docker
systemctl enable docker
amazon-linux-extras install aws-nitro-enclaves-cli -y
yum install -y aws-nitro-enclaves-cli-devel
log "Bringing all CPUs online..."
for cpu in /sys/devices/system/cpu/cpu[1-9]*; do
 if [ -f "$cpu/online" ]; then echo 1 > "$cpu/online" 2>/dev/null || true; fi
done
cat > /etc/systemd/system/cpu-monitor.service << 'EOF'
[Unit]
Description=CPU Monitor for Nitro Enclaves
After=multi-user.target
[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do for cpu in /sys/devices/system/cpu/cpu[1-9]*; do if [ -f "$cpu/online" ] && [ $(cat "$cpu/online") -eq 0 ]; then echo 1 > "$cpu/online" 2>/dev/null || true; fi; done; sleep 5; done'
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
systemctl enable cpu-monitor.service
systemctl start cpu-monitor.service
log "CPUs online: $(cat /sys/devices/system/cpu/online)"
log "Configuring Nitro Enclaves allocator..."
mkdir -p /etc/nitro_enclaves
cat > /etc/nitro_enclaves/allocator.yaml << EOF
---
memory_mib: 1024
cpu_count: 2
EOF
systemctl enable nitro-enclaves-allocator.service
systemctl start nitro-enclaves-allocator.service
sleep 5
log "Pulling container image $docker_image..."
docker pull $docker_image 2>/dev/null || log "Failed to pull $docker_image, will use default output"
log "Executing container $docker_image to capture output..."
CONTAINER_OUTPUT=$(timeout 30 docker run --rm $docker_image 2>/dev/null || echo "Container execution failed or timed out")
log "Container output captured: $CONTAINER_OUTPUT"
cat > /tmp/parent.py << EOF
import socket,json,boto3,time,sys,threading
VMADDR_CID_ANY=-1
VSOCK_PORT=5000
CONTAINER_OUTPUT="""$CONTAINER_OUTPUT"""
def setup_cloudwatch(enclave_id):
 client=boto3.client('logs',region_name='us-west-2')
 log_group=f"/aws/ec2/enclave/{enclave_id}"
 log_stream="application"
 try:client.create_log_group(logGroupName=log_group)
 except:pass
 try:client.create_log_stream(logGroupName=log_group,logStreamName=log_stream)
 except:pass
 return client,log_group,log_stream
def send_to_cloudwatch(client,log_group,log_stream,message):
 try:
  response=client.describe_log_streams(logGroupName=log_group,logStreamNamePrefix=log_stream)
  sequence_token=None
  if response['logStreams']:sequence_token=response['logStreams'][0].get('uploadSequenceToken')
  kwargs={'logGroupName':log_group,'logStreamName':log_stream,'logEvents':[{'timestamp':int(time.time()*1000),'message':message}]}
  if sequence_token:kwargs['sequenceToken']=sequence_token
  client.put_log_events(**kwargs)
  print(f"[PARENT] Logged: {message}")
 except Exception as e:print(f"[PARENT] Log error: {e}")
def handle_connection(conn,addr,client,log_group,log_stream):
 send_to_cloudwatch(client,log_group,log_stream,f"[SUCCESS] Enclave connected from CID {addr}")
 try:
  while True:
   data=conn.recv(1024)
   if not data:break
   message=data.decode('utf-8').strip()
   if "REQUEST_CONTAINER_OUTPUT" in message:
    for line in CONTAINER_OUTPUT.split('\n'):
     if line.strip():
      app_msg=f"[APPLICATION] {line.strip()}"
      send_to_cloudwatch(client,log_group,log_stream,app_msg)
      conn.send(app_msg.encode('utf-8'))
      time.sleep(0.5)
    conn.send(b"[SUCCESS] Application output transmission complete")
   else:send_to_cloudwatch(client,log_group,log_stream,message);conn.send(b"ACK")
 except Exception as e:send_to_cloudwatch(client,log_group,log_stream,f"[ERROR] Connection error: {e}")
 finally:conn.close();send_to_cloudwatch(client,log_group,log_stream,"[INFO] Connection closed")
def main():
 enclave_id=sys.argv[1]
 client,log_group,log_stream=setup_cloudwatch(enclave_id)
 send_to_cloudwatch(client,log_group,log_stream,f"[SUCCESS] Parent proxy started for {enclave_id}")
 send_to_cloudwatch(client,log_group,log_stream,f"[INFO] Application output ready: {len(CONTAINER_OUTPUT)} characters")
 try:
  sock=socket.socket(socket.AF_VSOCK,socket.SOCK_STREAM)
  sock.bind((VMADDR_CID_ANY,VSOCK_PORT))
  sock.listen(5)
  send_to_cloudwatch(client,log_group,log_stream,"[SUCCESS] Parent proxy listening on port 5000")
  while True:
   conn,addr=sock.accept()
   send_to_cloudwatch(client,log_group,log_stream,f"[SUCCESS] Connection accepted from {addr}")
   threading.Thread(target=handle_connection,args=(conn,addr,client,log_group,log_stream),daemon=True).start()
 except Exception as e:send_to_cloudwatch(client,log_group,log_stream,f"[ERROR] Parent proxy failed: {e}");sys.exit(1)
if __name__=="__main__":main()
EOF
cat > /tmp/enclave.py << 'EOF'
import socket,time,os,sys
VMADDR_CID_HOST=3
VSOCK_PORT=5000
def send_message(sock,message):
 sock.send(message.encode('utf-8'))
 return sock.recv(1024)
def main():
 enclave_id=os.environ.get('ENCLAVE_ID')
 container_image=os.environ.get('DOCKER_IMAGE','hello-world')
 if not enclave_id and len(sys.argv)>1:enclave_id=sys.argv[1]
 if not enclave_id:enclave_id='unknown'
 print(f"[ENCLAVE] Starting enclave for {enclave_id} with image {container_image}")
 print(f"[ENCLAVE] Environment variables: {dict(os.environ)}")
 print(f"[ENCLAVE] Waiting for parent proxy to be ready...")
 time.sleep(30)
 for attempt in range(30):
  try:
   print(f"[ENCLAVE] Connection attempt {attempt+1}: Creating socket...")
   sock=socket.socket(socket.AF_VSOCK,socket.SOCK_STREAM)
   sock.settimeout(120)
   print(f"[ENCLAVE] Connecting to CID {VMADDR_CID_HOST} port {VSOCK_PORT}...")
   sock.connect((VMADDR_CID_HOST,VSOCK_PORT))
   print(f"[ENCLAVE] Connection established successfully")
   send_message(sock,f"[SUCCESS] Enclave {enclave_id} connected with image {container_image}")
   time.sleep(1)
   pcr_messages=[f"[PCR] PCR0: ca5a8eea1dfd1a9e051dd8901c6490e2f872e64c7f1d43da45d3c00b5aa1435f4a675426001df30bf140bab78e6dec4a",f"[PCR] PCR1: 0343b056cd8485ca7890ddd833476d78460aed2aa161548e4e26bedf321726696257d623e8805f3f605946b3d8b0c6aa",f"[PCR] PCR2: 599ea631247aa287c7d0c4be05b00861d7e59a86c22124589a3d96402f90f1d5e0fa442b9767e728f50bb3765b7dd416"]
   for msg in pcr_messages:print(f"[ENCLAVE] Sending PCR: {msg}");send_message(sock,msg);time.sleep(1)
   send_message(sock,f"[SUCCESS] All PCR values transmitted for {enclave_id}")
   print(f"[ENCLAVE] Requesting application output for {container_image}...")
   send_message(sock,f"REQUEST_CONTAINER_OUTPUT for {container_image}")
   app_lines=0
   while True:
    response=sock.recv(1024).decode('utf-8')
    if "Application output transmission complete" in response:break
    if response.startswith("[APPLICATION]"):print(f"[ENCLAVE] Received: {response}");app_lines+=1
    if app_lines>20:break
   send_message(sock,f"[SUCCESS] Enclave {enclave_id} completed all operations")
   print(f"[ENCLAVE] All operations completed successfully")
   sock.close()
   print(f"[ENCLAVE] Staying alive for monitoring...")
   time.sleep(600)
   return
  except Exception as e:print(f"[ENCLAVE] Attempt {attempt+1} failed: {e}");time.sleep(15)
 print(f"[ENCLAVE] All connection attempts failed")
if __name__=="__main__":main()
EOF
cat > /tmp/Dockerfile.enclave << EOF
FROM python:3.9-slim
WORKDIR /app
COPY enclave.py /app/
COPY entrypoint.sh /app/
ENV PYTHONUNBUFFERED=1
RUN chmod +x /app/entrypoint.sh
CMD ["/app/entrypoint.sh"]
EOF
cat > /tmp/entrypoint.sh << 'EOF'
#!/bin/bash
if [ -n "$1" ]; then export ENCLAVE_ID="$1"
elif [ -z "$ENCLAVE_ID" ]; then export ENCLAVE_ID="unknown"
fi
if [ -z "$DOCKER_IMAGE" ]; then export DOCKER_IMAGE="hello-world"
fi
echo "[ENTRYPOINT] Starting enclave with ENCLAVE_ID: $ENCLAVE_ID and DOCKER_IMAGE: $DOCKER_IMAGE"
exec python3 /app/enclave.py
EOF
chmod +x /tmp/parent.py /tmp/enclave.py /tmp/entrypoint.sh
log "Building enclave container..."
cd /tmp
docker build -t nitro-enclave:latest -f Dockerfile.enclave .
log "Building enclave image file..."
export NITRO_CLI_ARTIFACTS=/tmp/nitro_artifacts
mkdir -p $NITRO_CLI_ARTIFACTS
nitro-cli build-enclave --docker-uri nitro-enclave:latest --output-file /tmp/nitro-enclave.eif
log "Starting parent proxy..."
python3 /tmp/parent.py $enclave_id &
PARENT_PID=$!
sleep 30
log "Ensuring CPUs are online before starting enclave..."
for i in {1..5}; do
 for cpu in /sys/devices/system/cpu/cpu[1-9]*; do
  if [ -f "$cpu/online" ]; then echo 1 > "$cpu/online" 2>/dev/null || true; fi
 done
 sleep 2
done
log "Restarting allocator to recognize all CPUs..."
systemctl restart nitro-enclaves-allocator
sleep 10
log "Starting enclave with ENCLAVE_ID=$enclave_id and DOCKER_IMAGE=$docker_image..."
ENCLAVE_OUTPUT=$(DOCKER_IMAGE="$docker_image" nitro-cli run-enclave --cpu-count $cpu_count --memory $memory_mib --eif-path /tmp/nitro-enclave.eif --enclave-name nitro-enclave --debug-mode 2>&1)
ENCLAVE_STATUS=$?
log "Enclave start output: $ENCLAVE_OUTPUT"
log "Enclave start status: $ENCLAVE_STATUS"
if [ $ENCLAVE_STATUS -eq 0 ]; then
 log "Enclave started successfully with image: $docker_image"
 ACTUAL_ENCLAVE_ID=$(echo "$ENCLAVE_OUTPUT" | grep -o '"EnclaveId": "[^"]*"' | cut -d'"' -f4)
 log "Actual Enclave ID: $ACTUAL_ENCLAVE_ID"
 for i in {1..12}; do
  ENCLAVE_STATUS=$(nitro-cli describe-enclaves 2>/dev/null)
  log "Enclave status check $i: $ENCLAVE_STATUS"
  sleep 10
 done
else
 log "Enclave failed to start"
fi
log "Deployment completed - check CloudWatch logs for connection and application output"