
%1 mshta vbscript:CreateObject("Shell.Application").ShellExecute("cmd.exe","/c %~s0 ::","","runas",1)(window.close)&&exit


date 2012/9/10
TIMEOUT /T 3
start Xshell 
start Xftp
TIMEOUT /T 3

net stop w32time
net start w32time