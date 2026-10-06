#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>
#include <time.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <sys/file.h>
static volatile sig_atomic_t stopped=0;
static void request_stop(int sig) { (void)sig; stopped=1; }
int main(int argc,char **argv) {
 if(argc<3) return 64;
 char *end=0; long expected=strtol(argv[1],&end,10);
 if(!end || *end || expected<=1 || expected!=getppid()) return 64;
 pid_t owner=(pid_t)expected;
 int engine_index=2; int lease_fd=-1;
 if(strncmp(argv[2],"--lease=",8)==0) {
  if(argc<4) return 64;
  lease_fd=open(argv[2]+8,O_RDWR|O_CREAT,0600);
  if(lease_fd<0 || flock(lease_fd,LOCK_EX|LOCK_NB)!=0) return 73;
  engine_index=3;
 }
 // Engine inherits this lock too. Capacity remains reserved until the entire
 // owned engine has exited, even if its controller crashes during shutdown.
 struct sigaction action={0}; action.sa_handler=request_stop;
 sigaction(SIGTERM,&action,0); sigaction(SIGINT,&action,0); sigaction(SIGHUP,&action,0);
 pid_t child=fork(); if(child<0) return 71;
 if(child==0) {
  setpgid(0,0);
  signal(SIGINT,SIG_DFL); signal(SIGTERM,SIG_DFL); signal(SIGHUP,SIG_DFL);
  execv(argv[engine_index],argv+engine_index); perror("Unable to launch mining engine"); _exit(127);
 }
 setpgid(child,child);
 int status=0; int stopping=0; struct timespec began={0};
 for(;;) {
  pid_t result=waitpid(child,&status,WNOHANG);
  if(result==child) return WIFEXITED(status)?WEXITSTATUS(status):128+WTERMSIG(status);
  if(result<0 && errno!=EINTR) return 72;
  if(!stopping && (stopped || getppid()!=owner)) {
   stopping=1; clock_gettime(CLOCK_MONOTONIC,&began); kill(-child,SIGINT);
  }
  if(stopping) {
   struct timespec now; clock_gettime(CLOCK_MONOTONIC,&now);
   if(now.tv_sec-began.tv_sec>=3) kill(-child,SIGKILL);
  }
  struct timespec delay={0,100000000}; nanosleep(&delay,0);
 }
}
