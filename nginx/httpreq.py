import os
import time
http_req_cmd = "wget localhost:8080 -O /dev/null"
time_start = time.time()

while(1):    
    os.system(http_req_cmd)
    time.sleep(0.3)
    print("----------------")
    time_duration = time.time() - time_start
    if (time_duration > 60*10):
        break