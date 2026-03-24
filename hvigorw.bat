@rem ##########################################################################
@rem
@rem  hvigorw startup script for Windows
@rem
@rem ##########################################################################
@echo off
set HVIGOR_HOME=%USERPROFILE%\.hvigor\wrapper\tools
set DEFAULT_JVM_OPTS="-Xmx2048m" "-Dfile.encoding=UTF-8"
set CLASSPATH=%HVIGOR_HOME%\hvigor-wrapper.jar
java %DEFAULT_JVM_OPTS% -classpath "%CLASSPATH%" com.huawei.hvigor.wrapper.BootstrapMain %*
