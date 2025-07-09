FROM arm64v8/ubuntu:latest

# Set timezone to Asia/Shanghai
RUN apt-get update && apt-get install -y tzdata && \
    ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata

# Install curl, ca-certificates, redis, supervisor and mariadb-server-10.6
# 使用阿里云镜像源并添加重试机制
RUN echo "Acquire::Retries \"3\";" > /etc/apt/apt.conf.d/80-retries && \
    echo "Acquire::http::Timeout \"30\";" >> /etc/apt/apt.conf.d/80-retries && \
    sed -i 's/http:\/\/archive.ubuntu.com\/ubuntu\//http:\/\/mirrors.aliyun.com\/ubuntu\//g' /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        redis-server \
        supervisor && \
    # 单独安装 MariaDB（如果有问题）
    apt-get install -y --no-install-recommends software-properties-common && \
    apt-key adv --fetch-keys 'https://mariadb.org/mariadb_release_signing_key.asc' && \
    add-apt-repository 'deb [arch=arm64] http://mirrors.aliyun.com/mariadb/repo/10.6/ubuntu jammy main' && \
    apt-get update && \
    apt-get install -y --no-install-recommends mariadb-server-10.6 && \
    rm -rf /var/lib/apt/lists/* \

# 创建 supervisor 配置目录
RUN mkdir -p /etc/supervisor/conf.d

# 创建 supervisord.conf 配置文件
RUN echo '[supervisord]' > /etc/supervisor/supervisord.conf && \
    echo 'nodaemon=true' >> /etc/supervisor/supervisord.conf && \
    echo 'user=root' >> /etc/supervisor/supervisord.conf && \
    # 设置日志级别为 warn
    echo 'loglevel=warn' >> /etc/supervisor/supervisord.conf && \
    echo '[unix_http_server]' >> /etc/supervisor/supervisord.conf && \
    echo 'file=/var/run/supervisor.sock' >> /etc/supervisor/supervisord.conf && \
    echo 'chmod=0700' >> /etc/supervisor/supervisord.conf && \
    # 添加身份验证配置
    echo 'username=admin' >> /etc/supervisor/supervisord.conf && \
    echo 'password=yourpassword' >> /etc/supervisor/supervisord.conf && \
    echo '[supervisorctl]' >> /etc/supervisor/supervisord.conf && \
    echo 'serverurl=unix:///var/run/supervisor.sock' >> /etc/supervisor/supervisord.conf && \
    echo 'username=admin' >> /etc/supervisor/supervisord.conf && \
    echo 'password=yourpassword' >> /etc/supervisor/supervisord.conf && \
    echo '[rpcinterface:supervisor]' >> /etc/supervisor/supervisord.conf && \
    echo 'supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface' >> /etc/supervisor/supervisord.conf && \
    echo '[include]' >> /etc/supervisor/supervisord.conf && \
    echo 'files = /etc/supervisor/conf.d/*.conf' >> /etc/supervisor/supervisord.conf

# Add supervisor config for redis
RUN echo '[program:redis]' > /etc/supervisor/conf.d/01_redis.conf && \
    echo 'command=/usr/bin/redis-server' >> /etc/supervisor/conf.d/01_redis.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/01_redis.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/01_redis.conf && \
    echo 'stderr_logfile=/var/log/redis.err.log' >> /etc/supervisor/conf.d/01_redis.conf && \
    echo 'stdout_logfile=/var/log/redis.out.log' >> /etc/supervisor/conf.d/01_redis.conf

# Add supervisor config for mariadb
RUN echo '[program:mariadb]' > /etc/supervisor/conf.d/02_mariadb.conf && \
    echo 'command=/usr/bin/mysqld_safe' >> /etc/supervisor/conf.d/02_mariadb.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/02_mariadb.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/02_mariadb.conf && \
    echo 'stderr_logfile=/var/log/mariadb.err.log' >> /etc/supervisor/conf.d/02_mariadb.conf && \
    echo 'stdout_logfile=/var/log/mariadb.out.log' >> /etc/supervisor/conf.d/02_mariadb.conf

# Add supervisor config for myapp，添加参数让 myapp 监听 8849 端口
RUN echo '[program:myapp]' > /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'command=/app/myapp' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'stdout_logfile=/dev/stdout' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'stdout_logfile_maxbytes=0' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'redirect_stderr=true' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'stderr_logfile=/dev/stderr' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'stderr_logfile_maxbytes=0' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'stdout_events_enabled=true' >> /etc/supervisor/conf.d/99_myapp.conf

# 设置 MariaDB root 密码并创建数据库
RUN service mariadb start && \
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'Iwe@12345678'; FLUSH PRIVILEGES;" && \
    mysql -u root -pIwe@12345678 -e "CREATE DATABASE iwedb;"

LABEL maintainer="exthirteen"
ENV LANG=C.UTF-8

WORKDIR /app
ADD myapp /app/myapp
ADD assets /app/assets
ADD static /app/static

# 暴露 8849 端口
EXPOSE 8849
# 修改启动命令，指定配置文件路径
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]