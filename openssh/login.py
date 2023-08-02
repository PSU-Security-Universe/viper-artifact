from pexpect import pxssh
import getpass
import timeout_decorator

@timeout_decorator.timeout(10)
def login(username, password):
    try:
        """
        s = pxssh.pxssh(timeout=10, options={
                "StrictHostKeyChecking": "no",
                "UserKnownHostsFile": "/dev/null",
                "PreferredAuthentications": "password",
                "PubkeyAuthentication": "no",
            })
        """
        s = pxssh.pxssh()

        hostname = "localhost"
        port = 2022
        s.login(hostname, username, password, port=port)
        print("[!] Login Successfully.")
        s.logout()
    except pxssh.ExceptionPxssh as e:
        print("Failed to login:", e)
    except Exception as e :
        print("Exception:", e)

def main():
    right_user = getpass.getuser()
    wrong_passwd = "123"
    while 1:
        login(right_user, wrong_passwd)

if __name__ == "__main__":
    main()
