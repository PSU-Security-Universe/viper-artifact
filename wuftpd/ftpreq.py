# !/usr/bin/python
# coding: utf-8
# -*- coding: utf-8 -*-
from ftplib import FTP
import time
import getpass

from ftplib import FTP
def ftpconnect(host, username, password):
  ftp = FTP()
  # ftp.set_debuglevel(2)
  ftp.connect(host, 21)
  ftp.login(username, password)
  return ftp
def downloadfile(ftp, remotepath, localpath):
  bufsize = 1024
  fp = open(localpath, 'wb')
  ftp.retrbinary('RETR ' + remotepath, fp.write, bufsize)
  ftp.set_debuglevel(0)
  fp.close()
def uploadfile(ftp, remotepath, localpath):
  bufsize = 1024
  fp = open(localpath, 'rb')
  ftp.storbinary('STOR ' + remotepath, fp, bufsize)
  ftp.set_debuglevel(0)
  fp.close()


if __name__ == "__main__":
  time_start = time.time()

  while(1):
    while (1):
      try:
        right_user = getpass.getuser()
        right_pass = "<right_password>"
        ftp = ftpconnect("127.0.0.1", right_user, right_pass) # edit to your username & password
        break
      #except (ConnectionRefusedError, EOFError):
      except:
        print("can not connect")
        time.sleep(1)
        continue

    try:
        downloadfile(ftp, "./test/1", "./download/1")
    except:
        print("download error")
        time.sleep(0.5)
    #uploadfile(ftp, "C:/Users/Administrator/Desktop/test.mp4", "test.mp4")
    try:
        ftp.quit()
    except:
        print("quit error")
        time.sleep(0.5)
    print("finished!")
    time.sleep(1)
    print("----------------")
    time_duration = time.time() - time_start
    if (time_duration > 3000):
        break
