#!/bin/bash
### BEGIN INIT INFO
# Provides:          teambox-firstboot
# Required-Start:    postgresql $remote_fs $syslog
# Required-Stop:     $remote_fs $syslog
# X-Start-Before:    kcd kcdnotif tbxsosd kwsfetcher
# Default-Start:     2 3 4 5
# Default-Stop:      
# Short-Description: Teambox Sign-On Server Daemon
# Description:       Teambox Sign-On Server Daemon
### END INIT INFO

TEAMBOX_HOME=/opt/teambox
BUILD_DIR=/tmp/TEAMBOX_BUILD

# Information about the organization that will be created. You don't really
# have to change this as it doesn't have much influence on the usability of
# the system.
ORG_NAME=teambox.co
KEY_ID=99999999

# GIT repository configuration
GIT_DEFAULT_TAG=R2

##
##
## UTILITY FUNCTIONS
##
## The functions here should be as distribution-agnostic as possible.
##

centos_PACKAGES="\
redhat-lsb-core \
gcc \ 
gcc-c++ \
glibc-devel \
git-all \
scons \
libgcrypt-devel \
libgcrypt \
flex \
python-psycopg2 \
PyGreSQL \
openldap-devel \
cyrus-sasl-devel \
apr-devel \
adns-devel \
readline-devel \
openssl-devel \
pkgconfig \
postgresql91-server \
postgresql91-devel \
postgresql91-libs \
httpd \
mod_wsgi \
gnutls-devel \
mhash-devel \
libjpeg-turbo-devel \
python-pip \
python-devel \
sqlite-devel"

debian_PACKAGES="\
python-virtualenv \
python-dev \
postgresql-server-dev-9.1 \
psmisc \
sudo \
git-core \
build-essential \
scons \
libgcrypt11-dev \
flex \
python-psycopg2 \
python-pygresql \
libldap2-dev \
libsasl2-dev \
libadns1-dev \
libapr1-dev \
libreadline6-dev \
libpq-dev \
openssl \
pkg-config \
postgresql-9.1 \
libsqlite3-dev \
apache2 \
libapache2-mod-wsgi \
libgnutls-dev \
libmhash-dev \
libjpeg62-dev"

#
# Detect the distribution.
# Taken from: 
#   http://www.linux-tips-and-tricks.de/index.php/latest/how-to-find-out-which-linux-distribution-a-bash-script-runs-on.html
#
detect_distribution() {
    local var=$1
    local detectedDistro="unknown"
    local regExpLsbInfo="Description:[[:space:]]*([^ ]*)"
    local regExpLsbFile="/etc/(.*)[-_]"
    
    if [ `which lsb_release 2>/dev/null` ]; then       # lsb_release available
        lsbInfo=`lsb_release -d`
        if [[ $lsbInfo =~ $regExpLsbInfo ]]; then
            detectedDistro=${BASH_REMATCH[1]}
        else
            echo "??? Should not occur: Don't find distro name in lsb_release output ???"
            exit 1
        fi
    else
        etcFiles=`ls /etc/*[-_]{release,version} 2>/dev/null`
        for file in $etcFiles; do
            if [[ $file =~ $regExpLsbFile ]]; then
                detectedDistro=${BASH_REMATCH[1]}
                break
            else
                echo "??? Should not occur: Don't find any etcFiles ???"
                exit 1
            fi
        done
    fi
    
    detectedDistro=`echo $detectedDistro | tr "[:upper:]" "[:lower:]"`

    case $detectedDistro in
        suse)   detectedDistro="opensuse" ;;
        linux)  detectedDistro="linuxmint" ;;
    esac

    eval "$var=$detectedDistro"
}

template() {
    local target=$1
    local hostname ip addr lookup
    ip=$(ifconfig  | grep 'inet addr:'| grep -v '127.0.0.1' | cut -d: -f2 | awk '{print $1}' | head -1)
    
    addr=$ip
    if [ ! -z "$(which nslookup 2> /dev/null)" ]; then
        lookup=$(nslookup $ip)
        if [ $? = 0 ]; then
            addr=$(echo $lookup | grep Name | awk '{print $2}')
        fi
    fi

    sed -i \
        -e "s|@@PREFIX@@|"${TEAMBOX_HOME}"|g" \
        -e "s|@@HOSTNAME@@|$addr|g" $target
}

make_directory() {
    # Install directory
    mkdir -p $TEAMBOX_HOME
    mkdir -p $TEAMBOX_HOME/lib
    
    # Build directory
    mkdir -p $BUILD_DIR

    PATH=$PATH:$TEAMBOX_HOME/bin

    # We add our libraries to the libraries of the system through this
    echo "$TEAMBOX_HOME/lib" > /etc/ld.so.conf.d/teambox.conf
}

run_service() {
    # TODO: IMPROVE
    /etc/init.d/$1 start
}

# Generates a self-signed SSL certificate.
generate_ssl() {
    local target_dir=$1
    local req_name=$2
    local key_name=$3
    local cert_name=$4
    local conf_name=$5

    if [ ! -d $target_dir ]; then
        mkdir -p $target_dir
    fi

    openssl genrsa -out $target_dir/$key_name 1024
    cat > $target_dir/$conf_name <<EOF
[ req ]
default_bits       = 1024
default_keyfile    = keyfile.pem
distinguished_name = req_distinguished_name
prompt             = no
output_password    = mypass

[ req_distinguished_name ]
C  = CA
ST = Quebec
L  = Sherbrooke
O  = Teambox
CN = Common Name
emailAddress = fdgonthier@lostwebsite.net
EOF
    openssl req -new \
        -key $target_dir/$key_name \
        -config $target_dir/$conf_name \
        -out $target_dir/$req_name
    openssl x509 -req -days 9999 \
        -in $target_dir/$req_name \
        -signkey $target_dir/$key_name \
        -out $target_dir/$cert_name

}

generate_python_virtual_env() {
    local python_packages="\
beaker==1.3 \
decorator==3.3.1 \
Elixir==0.6.1 \
FormEncode==1.2.1 \
gp.fileupload==0.8 \
Mako==0.2.4 \
nose==1.3.0 \
Paste==1.7.2 \
PasteDeploy==1.3.3 \
PasteScript==1.7.3 \
Pygments==1.0 \
Pylons==0.9.7 \
Routes==1.10.3 \
setuptools==0.6c9 \
Shabti==0.3.2b \
simplejson==2.0.8 \
Tempita==0.2 \
WebError==0.10.1 \
WebHelpers==0.6.4 \
WebOb==0.9.6.1 \
WebTest==1.1 \
SQLAlchemy==0.5.5 \
psycopg2 \
pygresql \
pyopenssl \
"

    mkdir -p $TEAMBOX_HOME/share/teambox/

    # Create a Python virtual environment.
    if [ ! -d $TEAMBOX_HOME/share/teambox/virtualenv ]; then
        (cd $TEAMBOX_HOME/share/teambox/ && virtualenv virtualenv)
    fi
    [ $? -eq 0 ] || return 1

    # Install the packages in the virtual environment.
    (source $TEAMBOX_HOME/share/teambox/virtualenv/bin/activate &&
        pip install $python_packages >&2)

    return 0
}

# Set the password of a PostgreSQL to a random UUID as provided
# by the system. Returns that password so it can be used in a 
# file template.
postgresql_random_password() {
    local user=$1
    local retvar=$2
    local password=$(cat /proc/sys/kernel/random/uuid)

    sudo -u postgres psql -c "ALTER USER $user PASSWORD '$password'"
    eval "$retvar=$password"
}

password_fix_all() {
    local kcd_pwd

    for pg in $TEAMBOX_HOME/share/teambox/db/??-*.sqlpy; do
        sudo -u postgres PYTHONPATH=$PYTHONPATH \
            $TEAMBOX_HOME/bin/kexecpg --switch create $pg
    done

    # Change the KCD root password.
    kcd_pwd=$(cat /proc/sys/kernel/random/uuid)
    echo $kcd_pwd > $TEAMBOX_HOME/etc/base/admin_pwd
    sed -i "s/'kcd_pwd'.*/'kcd_pwd', '$kcd_pwd'\),/g" \
        $TEAMBOX_HOME/etc/base/master.cfg

    # PostgreSQL database passwords
    postgresql_random_password kcd kcd_pwd
    postgresql_random_password kwmo kwmo_pwd
    postgresql_random_password freemium freemium_pwd
    postgresql_random_password tbxsosd tbxsosd_pwd
    postgresql_random_password xmlrpc xmlrpc_pwd

    sed -i "s/db_password.*=.*/db_password=$kcd_pwd/g" \
        $TEAMBOX_HOME/etc/kcd/kcd.ini
    sed -i "s/kwmo_db_pwd.*=.*/kwmo_db_pwd = $kwmo_pwd/g" \
        $TEAMBOX_HOME/www/kwmo/production.ini
    sed -i "s/kcd_db_pwd.*=.*/kcd_db_pwd = $kcd_pwd/g" \
        $TEAMBOX_HOME/www/kwmo/production.ini
    sed -i "s/freemium_db_pwd.*=.*/freemium_db_pwd = $freemium_pwd/g" \
        $TEAMBOX_HOME/www/freemium/production.ini
    sed -i "s/db_pwd.*=.*/db_pwd = $freemium_pwd/g" \
        $TEAMBOX_HOME/etc/tbxsosd/tbxsos-xmlrpc.ini
    sed -i "s/db.password.*=.*/db.password = \"$tbxsosd_pwd\";/g" \
        $TEAMBOX_HOME/etc/tbxsosd/db.conf
    sed -i "s/db.admin_password.*=.*/db.admin_password = \"$tbxsosd_pwd\";/g" \
        $TEAMBOX_HOME/etc/tbxsosd/db.conf
    sed -i "s/db_pwd.*=.*/db_pwd = $xmlrpc_pwd/g" \
        $TEAMBOX_HOME/etc/tbxsosd/tbxsos-xmlrpc.ini
    sed -i "s/freemium_db_pwd.*=.*/freemium_db_pwd = $freemium_pwd/g" \
        $TEAMBOX_HOME/etc/tbxsosd/tbxsos-xmlrpc.ini
    sed -i "s/'kcd_db_pwd'.*/'kcd_db_pwd', '$kcd_pwd'\),/g" \
        $TEAMBOX_HOME/etc/base/master.cfg
}

#
# Make the essential post-installation tasks on the system.
# 
configure_teambox() {
    local kctl=$TEAMBOX_HOME/bin/kctl

    mkdir -p $TEAMBOX_HOME/etc/keys

    # Generate the TBXSOSD keys
    (cd $TEAMBOX_HOME/etc/keys && $kctl genkeys both $KEY_ID master $ORG_NAME)

    # Import the keys.
    for kf in $TEAMBOX_HOME/etc/keys/*; do
        $kctl importkey $kf
    done

    # Generate an organization
    $kctl addorg $ORG_NAME $KEY_ID

    # Add the key at the end of the KCD configuration file.
    echo "$KEY_ID=$ORG_NAME" >> $TEAMBOX_HOME/etc/kcd/kcd.ini
}

#
# Fix the pending hostname in the server configuration
#
fix_hostnames() {
    template /opt/teambox/etc/tbxsosd/server.conf
    template /opt/teambox/etc/kcd/kcd.ini
}

##
##
## DISTRIBUTION SPECIFIC CODE
##
##

#
# Start of CentOS 6 functions
# 

# Do early initialization of the install. Make sure all the component.
centos_install_packages() {
    local arch pg_arch rpmforge_rpm_url rpmforge_rpm_file

    # Initialize the service names
    os_postgresql_service=postgresql-9.1
    os_httpd_service=httpd
    os_apache_dir=/etc/httpd/conf.d

    # Install 2 repositories that include packages that we need that
    # are missing from the default CentOS distribution.

    arch=$(uname -m)
    if [ "$arch" == "i686" ]; then
        pg_arch=i386
    else
        pg_arch=$arch
    fi

    # Install wget since we need it now.
    yum install -y wget

    # Install the PostgreSQL RPM repository
    pg_rpm_url="http://yum.postgresql.org/9.1/redhat/rhel-6-${pg_arch}/"
    pg_rpm_file="pgdg-centos91-9.1-4.noarch.rpm"
    if [ ! -e $BUILD_DIR/$pg_rpm_file ]; then
        (cd $BUILD_DIR && wget -q $pg_rpm_url/$pg_rpm_file && rpm -i $pg_rpm_file)
    fi
    
    # Install the RPM Forge repository (for ADNS)
    rpmforge_rpm_url="http://packages.sw.be/rpmforge-release/"
    rpmforge_rpm_file="rpmforge-release-0.5.2-2.el6.rf.${arch}.rpm"
    rpm --import http://apt.sw.be/RPM-GPG-KEY.dag.txt
    if [ ! -e $BUILD_DIR/$rpmforge_rpm_file ]; then
        (cd $BUILD_DIR && wget -q $rpmforge_rpm_url/$rpmforge_rpm_file && rpm -i $rpmforge_rpm_file)
    fi
    
    epel_rpm_url="http://mirrors.nl.eu.kernel.org/fedora-epel/6/${pg_arch}/"
    epel_rpm_file="epel-release-6-8.noarch.rpm"
    if [ ! -e $BUILD_DIR/$epel_rpm_file ]; then
        (cd $BUILD_DIR && wget -q $epel_rpm_url/$epel_rpm_file && rpm -i $epel_rpm_file)
    fi

    # Install all the packages.
    yum install -y $centos_PACKAGES

    # Update PATH and LD_LIBRARY_PATH so that the rest of the script
    # knows that PostgreSQL is installed.
    export PATH=$PATH:/usr/pgsql-9.1/bin
    export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/pgsql-9.1/lib

    # Install python-virtualenv through pip
    pip install virtualenv

    # Enable the daemons we just installed
    if [ ! -d /var/lib/pgsql/9.1/data/base ]; then
        service $os_postgresql_service initdb
    fi

    # Fix the PostgreSQL authentication configuration. I don't like
    # the idea of doing that but the default authentication will
    # always be too restrictive for this system.
    sed -i "s/host.*all.*all.*::1\/128.*ident/host\t\tall\t\tall\t\t::1\/128\tmd5/g" \
        /var/lib/pgsql/9.1/data/pg_hba.conf    

    chkconfig $os_postgresql_service on
    service $os_postgresql_service start

    chkconfig httpd on
    service httpd start
}

#
# End of CentOS 6 functions.
#

#
# Start of Debian 7 functions
#

ubuntu_install_packages() {
    debian_install_packages
}

debian_install_packages() {
    # Initialize the service names
    os_postgresql_service=postgresql
    os_httpd_service=apache2
    os_apache_dir=/etc/apache2/conf.d

    apt-get install -y $debian_PACKAGES
}

#
# End of Debian 7 functions
#

core_build() {
    local GIT_TEAMBOX_CORE

    if [ $opt_fdg = 1 ]; then
        GIT_TEAMBOX_CORE=https://github.com/fdgonthier/teambox-core.git
    else
        GIT_TEAMBOX_CORE=https://github.com/tmbx/teambox-core.git
    fi

    if [ ! -d $BUILD_DIR/teambox-core/.git ]; then
        (cd $BUILD_DIR && git clone $GIT_TEAMBOX_CORE)
        [ $? -eq 0 ] || return 1
        if [ $opt_usehead = 0 ]; then
            git --git-dir=$BUILD_DIR/teambox-core checkout $opt_gittag
            [ $? -eq 0 ] || return 1
        fi
    else
        if [ $opt_usehead = 1 ]; then
            git --git-dir=$BUILD_DIR/teambox-core checkout master
            [ $? -eq 0 ] || return 1
            git --git-dir=$BUILD_DIR/teambox-core pull
            [ $? -eq 0 ] || return 1
        fi
    fi
    (cd $BUILD_DIR/teambox-core &&
        scons --quiet --config=force \
            PREFIX='' \
            LIBDIR=$TEAMBOX_HOME/lib \
            BINDIR=$TEAMBOX_HOME/bin \
            PYTHONDIR=$TEAMBOX_HOME/share/teambox/python/ \
            DBDIR=$TEAMBOX_HOME/share/teambox/db \
            CONFDIR=$TEAMBOX_HOME/etc \
            INCDIR=$TEAMBOX_HOME/include)
    [ $? -eq 0 ] || return 1

    return 0
}

core_install() {
    if ! (cd $BUILD_DIR/teambox-core && scons --quiet install); then
        return 1
    else
        return 0;
    fi
}

tbxsosd_build() {
    local GIT_TBXSOSD
    
    mkdir -p $TEAMBOX_HOME/etc/tbxsosd
    [ $? -eq 0 ] || return 1

    if [ $opt_fdg = 1 ]; then
        GIT_TBXSOSD=https://github.com/fdgonthier/tbxsosd.git
    else
        GIT_TBXSOSD=https://github.com/tmbx/tbxsosd.git
    fi

    # Programs
    if [ ! -d $BUILD_DIR/tbxsosd/.git ]; then
        (cd $BUILD_DIR && git clone $GIT_TBXSOSD)
        [ $? -eq 0 ] || return 1
        if [ $opt_usehead = 0 ]; then
            git --git-dir=$BUILD_DIR/tbxsosd tag tags/$opt_gittag
            [ $? -eq 0 ] || return 1
        fi
    else
        if [ $opt_usehead = 1 ]; then
            git --git-dir=$BUILD_DIR/tbxsosd checkout master
            [ $? -eq 0 ] || return 1
            git --git-dir=$BUILD_DIR/tbxsosd pull
            [ $? -eq 0 ] || return 1
        fi
    fi
    (cd $BUILD_DIR/tbxsosd &&
        scons PREFIX=$TEAMBOX_HOME --config=force \
            tagcrypt_libpath=$TEAMBOX_HOME/lib \
            tagcrypt_include=$TEAMBOX_HOME/include \
            LIBDIR=$TEAMBOX_HOME/lib \
            INCDIR=$TEAMBOX_HOME/include \
            CONFDIR=$TEAMBOX_HOME/etc/tbxsosd \
            DBDIR=$TEAMBOX_HOME/share/teambox/db \
            PYTHONDIR=$TEAMBOX_HOME/share/teambox/python \
            BINDIR=$TEAMBOX_HOME/bin \
            APACHEDIR=$os_apache_dir \
            WWWDIR=$TEAMBOX_HOME/www)
    [ $? -eq 0 ] || return 1
   
    return 0
}

tbxsosd_install() {
    local pg_pwd

    # Runtime data directory.
    mkdir -p /var/cache/teambox/tbxsosd
    chown tbxsosd.tbxsosd /var/cache/teambox/tbxsosd

    (cd $BUILD_DIR/tbxsosd && scons --quiet install)
    [ $? -eq 0 ] || return 1
    
    # Init file.
    # TODO: Support other init systems.
    cp $BUILD_DIR/tbxsosd/init/tbxsosd /etc/init.d/tbxsosd
    template /etc/init.d/tbxsosd
    chmod +x /etc/init.d/tbxsosd
    if [ ! -z "$(which update-rc.d 2> /dev/null)" ]; then
        update-rc.d tbxsosd defaults
    elif [ ! -z "$(which chkconfig 2> /dev/null)" ]; then
        chkconfig --add tbxsosd
    fi

    # User & group
    getent passwd tbxsosd > /dev/null
    [ $? -eq 2 ] && useradd tbxsosd

    getent group tbxsosd > /dev/null
    [ $? -eq 2 ] && groupadd tbxsosd

    return 0
}

kmod_build() {
    local GIT_KMOD

    if [ $opt_fdg = 1 ]; then
        GIT_KMOD=https://github.com/fdgonthier/kmod.git
    else
        GIT_KMOD=https://github.com/tmbx/kmod.git
    fi

    # Programs
    if [ ! -d $BUILD_DIR/kmod/.git ]; then
        (cd $BUILD_DIR && git clone $GIT_KMOD)
        [ $? -eq 0 ] || return 1
        if [ $opt_usehead = 0 ]; then
            git --git-dir=$BUILD_DIR/kmod checkout tags/$opt_gittag
            [ $? -eq 0 ] || return 1
        fi
    else
        if [ $opt_usehead = 1 ]; then
            git --git-dir=$BUILD_DIR/kmod checkout master
            [ $? -eq 0 ] || return 1
            git --git-dir=$BUILD_DIR/kmod pull
            [ $? -eq 0 ] || return 1
        fi
    fi    
    (cd $BUILD_DIR/kmod && scons --quiet config DESTDIR=$TEAMBOX_HOME)
    [ $? -eq 0 ] || return 1

    (cd $BUILD_DIR/kmod && scons --quiet build)
    [ $? -eq 0 ] || return 1

    return 0
}

kmod_install() {
    # Kmod has no install target
    cp -v $BUILD_DIR/kmod/build/kmod/kmod $TEAMBOX_HOME/bin    
    [ $? -eq 0 ] || return 1

    return 0
}

kas_build() {
    local GIT_KAS

    if [ $opt_fdg = 1 ]; then
        GIT_KAS=https://github.com/fdgonthier/kas.git
    else
        GIT_KAS=https://github.com/tmbx/kas.git
    fi

    # Programs
    if [ ! -d $BUILD_DIR/kas/.git ]; then
        (cd $BUILD_DIR && git clone $GIT_KAS)
        [ $? -eq 0 ] || return 1
        if [ $opt_usehead = 0 ]; then
            git --git-dir=$BUILD_DIR/kas checkout tags/$opt_gittag
            [ $? -eq 0 ] || return 1
        fi
    else
        if [ $opt_usehead = 1 ]; then
            git --git-dir=$BUILD_DIR/kas checkout master
            [ $? -eq 0 ] || return 1
            git --git-dir=$BUILD_DIR/kas pull
            [ $? -eq 0 ] || return 1
        fi
    fi
    (cd $BUILD_DIR/kas && scons --quiet config \
        libktools_include=$TEAMBOX_HOME/include \
        libktools_lib=$TEAMBOX_HOME/lib \
        DBDIR=$TEAMBOX_HOME/share/teambox/db \
        DESTDIR=$TEAMBOX_HOME \
        CONFIG_PATH=$TEAMBOX_HOME/etc/ \
        PYTHONDIR=$TEAMBOX_HOME/share/teambox/python \
        WWWDIR=$TEAMBOX_HOME/www/ \
        VIRTUALENV=$TEAMBOX_HOME/share/teambox/virtualenv \
        APACHEDIR=$os_apache_dir \
        BINDIR=bin)
    [ $? -eq 0 ] || return 1

    (cd $BUILD_DIR/kas && scons --quiet build)
    [ $? -eq 0 ] || return 1

    return 0
}

# The KAS setup has multiple different components demanding to be handled
# in different ways.
# - Several binary daemons
# - 3 Python web application which demands to be used inside a Python virtual
#   environment.
# - A Python virtual environment, including several Python specific packages
#   need to be created for the web applications
# - Several PostgreSQL databases, configured through kexecpg.
kas_install() {
    local pg_libdir

    (cd $BUILD_DIR/kas && scons --quiet install)
    [ $? -eq 0 ] || return 1

    # PostgreSQL specific library
    pg_libdir=$(pg_config --pkglibdir)
    mv -v $TEAMBOX_HOME/usr/lib/postgresql/9.1/lib/libkcdpg.so $pg_libdir
    rmdir -v $TEAMBOX_HOME/usr/lib/postgresql/9.1/lib
    [ $? -eq 0 ] || return 1

    # Init file.
    cp $BUILD_DIR/kas/init/kcd.debian.init.in /etc/init.d/kcd
    template /etc/init.d/kcd
    cp $BUILD_DIR/kas/init/kwsfetcher.debian.init.in /etc/init.d/kwsfetcher
    template /etc/init.d/kwsfetcher
    cp $BUILD_DIR/kas/init/kcdnotif.debian.init.in /etc/init.d/kcdnotif
    template /etc/init.d/kcdnotif
    cp $BUILD_DIR/kas/init/kasmond.debian.init.in /etc/init.d/kasmond
    template /etc/init.d/kasmond

    chmod -v +x \
        /etc/init.d/kcd \
        /etc/init.d/kwsfetcher \
        /etc/init.d/kasmond \
        /etc/init.d/kcdnotif
    if [ ! -z "$(which update-rc.d 2> /dev/null)" ]; then
        update-rc.d kcd defaults
        update-rc.d kcdnotif defaults
        update-rc.d kwsfetcher defaults
    elif [ ! -z "$(which chkconfig 2> /dev/null)" ]; then
        chkconfig --add kcd
        chkconfig --add kcdnotif
        chkconfig --add kwsfetcher
    fi

    # KFS directory.
    mkdir -p /var/cache/teambox/kfs
    mkdir -p /var/cache/teambox/kwsfetcher

    # We need to run ldconfig at this point because PostgreSQL will
    # try to load libkcdpg.so, which requires libktools.
    ldconfig

    service $os_postgresql_service restart

    return $?
}

if [ $(id -u) != 0 ]; then
    echo "Must be run as root."
    exit 1
fi

opt_vmmode=0
opt_vmfirst=0
opt_gittag=$GIT_DEFAULT_TAG
opt_usehead=0
opt_keep=0
opt_fdg=0

firstboot='.*teambox-firstboot'
if [[ $0 =~ $firstboot ]]; then
    opt_vmfirst=1
fi

ARGS=$(getopt -o vht:hkf -l "vm,git-tag:,use-head,help,keep,fdg" -- "$@");
[ $? = 0 ] || exit 0
eval set -- "$ARGS";

while true; do
    case "$1" in
        -v|--vm)
            shift
            opt_vmmode=1
            ;;
        -h|--use-head)
            shift
            opt_usehead=0
            ;;
        -t|--git-tag)
            shift
            if [ -n "$1" ]; then
                opt_gittag=$1
                shift
            else
                echo "Missing argument to --git-tag."
                exit 1
            fi
            ;;
        -k|--keep)
            shift
            opt_keep=1
            ;;
        -f|--fdg)
            shift
            opt_fdg=1;
            ;;
        -h|--help)
            shift
            echo "Teambox Installer script"
            echo "Copyright Opersys Inc. 2013"
            echo ""
            echo "  --vm (-v)             VM mode install VM generating hooks                     "
            echo "  --keep (-k)           Keep the build directory $BUILD_DIR after               "
            echo "                        installation                                            "
            echo "  --fdg (-f)            Fetch from http://github.com/fdgonthier repositories    "
            echo "                        instead of the ordinary Teambox repositories.           "
            echo "  --git-tag (-t) [tag]  Fetch this release tag instead of the default one.      "
            exit 0
            ;;
        --)
            shift
            break
            ;;
    esac
done

allModules="core tbxsosd kmod kas"
allSteps="build install"

#exec 2>&1 > teambox-installer.log

if [ $opt_vmfirst = 0 ]; then
    detect_distribution dist
    
    if [ "$dist" != "debian" -a "$dist" != "ubuntu" -a "$dist" != "centos" ]; then
        echo "Distribution $dist not supported by this installer."
        exit 1
    fi

    make_directory

    ${dist}_install_packages

    echo "*** Killing Teambox services" >&2
    killall tbxsosd
    killall kcd
fi

# Generate SSL certificates for the sign-on service and
# the application service. Those are self-signed and can be 
# replaced if needed. The sign-on service SSL certificate
# are not currently used in the way the service is setup.
echo "*** Generating SSL keys" >&2
generate_ssl $TEAMBOX_HOME/etc/tbxsosd/ssl \
    tbxsosd.req tbxsosd.key tbxsosd.crt tbxsosd.cnf
generate_ssl $TEAMBOX_HOME/etc/kcd/ssl \
    kcd.req kcd.key kcd.crt kcd.cnf

if [ $opt_vmfirst = 0 ]; then
    echo "*** Installing Python virtual environment packages (don't hold your breath)" >&2
    generate_python_virtual_env
    if [ $? -eq 1 ]; then
        echo "FAILED" >&2
        exit
    else
        echo "OK" >&2
    fi

    for currentModule in $allModules; do
        for currentStep in $allSteps; do
            echo -n "*** Executing ${currentModule}_${currentStep}. " >&2
            ${currentModule}_${currentStep}
            if [ $? -eq 1 ]; then
                echo "FAILED" >&2
                exit
            else
                echo "OK" >&2
            fi
        done
    done
fi

# Don't execute this if we are producing a VM. It will be executed at
# first boot. In non VM mode, always execute.
if [ $opt_vmmode = 0 -o $opt_vmfirst = 1 ]; then
    password_fix_all
    configure_teambox
    fix_hostnames
fi

# Never executed except at first boot.
if [ $opt_vmfirst = 1 ]; then
    # Reconfigure the SSH keys.
    rm /etc/ssh/ssh_host_dsa_key*
    rm /etc/ssh/ssh_host_rsa_key*

    ssh-keygen -q -N '' -t dsa -f /etc/ssh/ssh_host_dsa_key
    ssh-keygen -q -N '' -t rsa -f /etc/ssh/ssh_host_rsa_key
    
    if [ ! -z "$(which update-rc.d 2> /dev/null)" ]; then
        update-rc.d teambox-firstboot remove
    else
        chkconfig --del teambox-firstboot
    fi
    rm /etc/init.d/teambox-firstboot
fi

# Install the hook for initthooks
if [ $opt_vmmode = 1 ]; then
    echo $PWD
    cp $0 /etc/init.d/teambox-firstboot
    if [ ! -z "$(which update-rc.d 2> /dev/null)" ]; then
        update-rc.d teambox-firstboot start 5 2 3 4 5
    elif [ ! -z "$(which chkconfig 2> /dev/null)" ]; then
        chkconfig --add teambox-firstboot
    fi
fi

# Restart the services.
if [ $opt_vmmode = 0 -a $opt_vmfirst = 0 ]; then
    run_service tbxsosd
    run_service kcd
    run_service kcdnotif
    run_service kwsfetcher

    echo "Please start or restart Apache immediately." >&2
fi

# Erase the build directory if required.
if [ $opt_keep = 0 ]; then
    rm -r $BUILD_DIR
fi
