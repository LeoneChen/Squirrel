FROM ubuntu:22.04

########## ROOT ##########
ARG USERNAME=leone
ARG USER_UID=1001
ARG USER_GID=$USER_UID

RUN sed -i "s/archive.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/" /etc/apt/sources.list
RUN sed -i "s/security.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/" /etc/apt/sources.list
RUN apt-get update

# Create the user
RUN groupadd --gid $USER_GID $USERNAME
RUN useradd --uid $USER_UID --gid $USER_GID -m $USERNAME

# Add sudo to user
RUN apt-get install -y sudo
RUN echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME
RUN chmod 0440 /etc/sudoers.d/$USERNAME
RUN usermod -aG sudo $USERNAME

# Add kvm sgx sgx_prv to user
RUN groupadd --gid 108 kvm
RUN groupadd --gid 136 sgx
RUN groupadd --gid 1003 sgx_prv
RUN usermod -aG kvm leone
RUN usermod -aG sgx leone
RUN usermod -aG sgx_prv leone

########## USER ##########
USER $USERNAME
WORKDIR /home/$USERNAME

# zsh in docker
RUN sudo apt-get install -y wget
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v1.2.0/zsh-in-docker.sh)" -- \
    -t robbyrussell \
    -p git \
    -p https://github.com/zsh-users/zsh-autosuggestions \
    -p https://github.com/zsh-users/zsh-completions

# Add proxy file
RUN cat <<EOF > /home/$USERNAME/proxy
#!/bin/bash
proxy_type="http"
proxy_ip="202.112.47.78"
proxy_port="20171"
export all_proxy="\${proxy_type}://\${proxy_ip}:\${proxy_port}"
export http_proxy="\${proxy_type}://\${proxy_ip}:\${proxy_port}"
export https_proxy="\${proxy_type}://\${proxy_ip}:\${proxy_port}"
export ftp_proxy="\${proxy_type}://\${proxy_ip}:\${proxy_port}"
EOF
RUN cat <<EOF > /home/$USERNAME/noproxy
#!/bin/bash
unset all_proxy
unset http_proxy
unset https_proxy
unset ftp_proxy
EOF

RUN sudo apt-get -y install make cmake build-essential vim sudo git clang clang-format lld ninja-build
RUN sudo apt-get -y install libmysqlclient-dev pkg-config libpq-dev libyaml-cpp-dev python3-fire
RUN sudo apt-get -y install apt-transport-https curl software-properties-common gnutls-dev

# install mariadb-server
RUN sudo curl -o /etc/apt/trusted.gpg.d/mariadb_release_signing_key.asc 'https://mariadb.org/mariadb_release_signing_key.asc'
RUN echo "deb https://ftp.osuosl.org/pub/mariadb/repo/10.11/ubuntu jammy main\ndeb-src https://ftp.osuosl.org/pub/mariadb/repo/10.11/ubuntu jammy main" | sudo tee /etc/apt/sources.list.d/mariadb.list
RUN sudo apt-get update
RUN sudo apt-get -y build-dep mariadb

WORKDIR /home/$USERNAME
RUN git clone https://github.com/LeoneChen/Squirrel.git -b noasan
WORKDIR /home/$USERNAME/Squirrel
RUN git submodule update --init
RUN cmake -B build -DCMAKE_BUILD_TYPE=Debug
RUN cmake --build build -j$(nproc)

WORKDIR /home/$USERNAME/Squirrel/AFLplusplus
RUN LLVM_CONFIG=llvm-config-14 make -j$(nproc)

WORKDIR /home/$USERNAME
RUN git clone https://github.com/MariaDB/server.git mariadb-server -b mariadb-10.11.11 --depth 1 
WORKDIR /home/$USERNAME/mariadb-server
RUN CC=/home/$USERNAME/Squirrel/AFLplusplus/afl-clang-fast CXX=/home/$USERNAME/Squirrel/AFLplusplus/afl-clang-fast++ cmake -B build
RUN cmake --build build -j$(nproc)
RUN cmake --install build --prefix /home/$USERNAME/mariadb-server/install
WORKDIR /home/$USERNAME/mariadb-server/install
RUN scripts/mysql_install_db --user=$USERNAME

# Get map size and save it to /tmp/mapsize
# RUN AFL_DEBUG=1 __AFL_SHM_ID=1234 /home/$USERNAME/mariadb-server/install/mariadbd 2>&1 | tail -n 1 | cut -d"," -f8 | cut -d" " -f 3 > /tmp/mapsize
# WORKDIR /home/Squirrel/scripts/utils
# ENTRYPOINT AFL_MAP_SIZE=$(cat /tmp/mapsize) python3 run.py mariadb ../../data/fuzz_root/mysql_input/
