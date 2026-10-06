#include <QGuiApplication>
#include <QTimer>
#include <KIdleTime>
#include <cstdio>
#include <unistd.h>
int main(int argc,char **argv) {
 QGuiApplication app(argc,argv);
 auto idle=KIdleTime::instance();
 const pid_t owner=getppid();
 QTimer heartbeat;
 QObject::connect(&heartbeat,&QTimer::timeout,[owner]{ if(getppid()!=owner) QCoreApplication::quit(); });
 heartbeat.start(2000);
 QObject::connect(idle,&KIdleTime::timeoutReached,[idle](int,int){puts("IDLE");fflush(stdout);idle->catchNextResumeEvent();});
 QObject::connect(idle,&KIdleTime::resumingFromIdle,[]{puts("ACTIVE");fflush(stdout);});
 idle->addIdleTimeout(300000);
 puts("WAITING");fflush(stdout);
 return app.exec();
}
