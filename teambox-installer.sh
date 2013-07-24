#!/bin/bash

TEAMBOX_HOME=/opt/teambox
BUILD_DIR=/tmp/TEAMBOX_BUILD

# Information about the organization that will be created. You don't really
# have to change this as it doesn't have much influence on the usability of
# the system.
ORG_NAME=teambox.co
KEY_ID=99999999

## UTILITY FUNCTIONS

template() {
    local from=$1 to=$2

    sed -e "s|@@PREFIX@@|"${TEAMBOX_HOME}"|g" \
        -e "s|@@HOSTNAME@@|"$(hostname --fqdn)"|g" $from > $to
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
pyopenssl
"
    local debian_packages="\
python-virtualenv \
python-dev \
postgresql-server-dev-9.1"

    # Install the packages required by the Python packages.
    apt-get -y install $debian_packages
    [ $? -eq 0 ] || return 1

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

## DISTRIBUTION SPECIFIC CODE

core_debian_init() {
    local pkgs="\
git-core \
build-essential \
scons \
libgcrypt11-dev \
flex \
python-psycopg2 \
python-pygresql"
    apt-get -y install $pkgs
    [ $? -eq 0 ] || return 1

    return 0
}

core_debian_build() {
    cd $BUILD_DIR
    if [ ! -d $BUILD_DIR/teambox-core/.git ]; then
        git clone https://github.com/fdgonthier/teambox-core.git
        [ $? -eq 0 ] || return 1
    else
        cd $BUILD_DIR/teambox-core && git pull
        [ $? -eq 0 ] || return 1
    fi
    cd $BUILD_DIR/teambox-core
    scons --quiet --config=force \
        PREFIX='' \
        LIBDIR=$TEAMBOX_HOME/lib \
        BINDIR=$TEAMBOX_HOME/bin \
        PYTHONDIR=$TEAMBOX_HOME/share/teambox/python/ \
        DBDIR=$TEAMBOX_HOME/share/teambox/db \
        CONFDIR=$TEAMBOX_HOME/etc \
        INCDIR=$TEAMBOX_HOME/include
    [ $? -eq 0 ] || return 1

    return 0
}

core_debian_install() {
    cd $BUILD_DIR/teambox-core
    if ! scons --quiet install; then
        return 1
    else
        return 0;
    fi
}

tbxsosd_debian_init() {
    local pkgs="\
libldap2-dev \
libsasl2-dev \
libadns1-dev \
libapr1-dev \
libreadline6-dev \
libpq-dev \
openssl \
pkg-config \
postgresql-9.1"
    apt-get -y install $pkgs
    [ $? -eq 0 ] || return 1

    mkdir -p $TEAMBOX_HOME/etc/tbxsosd
    [ $? -eq 0 ] || return 1

    return 0
}

tbxsosd_debian_build() {
    # Programs
    cd $BUILD_DIR
    if [ ! -d $BUILD_DIR/tbxsosd/.git ]; then
        git clone https://github.com/fdgonthier/tbxsosd.git
        [ $? -eq 0 ] || return 1
    else
        cd $BUILD_DIR/tbxsosd && git pull
        [ $? -eq 0 ] || return 1
    fi
    cd $BUILD_DIR/tbxsosd
    scons PREFIX=$TEAMBOX_HOME --config=force \
        tagcrypt_libpath=$TEAMBOX_HOME/lib \
        tagcrypt_include=$TEAMBOX_HOME/include \
        LIBDIR=$TEAMBOX_HOME/lib \
        INCDIR=$TEAMBOX_HOME/include \
        CONFDIR=$TEAMBOX_HOME/etc/tbxsosd \
        DBDIR=$TEAMBOX_HOME/share/teambox/db \
        PYTHONDIR=$TEAMBOX_HOME/share/teambox/python \
        BINDIR=$TEAMBOX_HOME/bin \
        WWWDIR=$TEAMBOX_HOME/www
    [ $? -eq 0 ] || return 1

    return 0
}

tbxsosd_debian_install() {
    local pg_pwd

    # Runtime data directory.
    mkdir -p /var/cache/teambox/tbxsosd
    chown tbxsosd.tbxsosd /var/cache/teambox/tbxsosd

    cd $BUILD_DIR/tbxsosd
    scons --quiet install
    [ $? -eq 0 ] || return 1
    
    # Init file.
    # TODO: Support other init systems.
    template init/tbxsosd /etc/init.d/tbxsosd
    chmod +x /etc/init.d/tbxsosd
    update-rc.d tbxsosd defaults

    # User & group
    getent passwd tbxsosd > /dev/null
    [ $? -eq 2 ] && useradd tbxsosd

    getent group tbxsosd > /dev/null
    [ $? -eq 2 ] && groupadd tbxsosd

    return 0
}

kmod_debian_init() {
    local pkgs="libsqlite3-dev"
    apt-get -y install $pkgs
    [ $? -eq 0 ] || return 1
    return 0
}

kmod_debian_build() {
    # Programs
    cd $BUILD_DIR
    if [ ! -d $BUILD_DIR/kmod/.git ]; then
        git clone https://github.com/fdgonthier/kmod.git
    else
        cd $BUILD_DIR/kmod && git pull
    fi    
    cd $BUILD_DIR/kmod
    scons --quiet config DESTDIR=$TEAMBOX_HOME
    [ $? -eq 0 ] || return 1

    scons --quiet build
    [ $? -eq 0 ] || return 1

    return 0
}

kmod_debian_install() {
    cd $BUILD_DIR/kmod
    
    # Kmod has no install target
    cp -v $BUILD_DIR/kmod/build/kmod/kmod $TEAMBOX_HOME/bin    
    [ $? -eq 0 ] || return 1

    return 0
}

kas_debian_init() {
    local pkgs="\
apache2 \
libapache2-mod-wsgi \
libgnutls-dev \
libmhash-dev \
libjpeg62-dev"
    apt-get -y install $pkgs
    [ $? -eq 0 ] || return 1
    return 0
}

kas_debian_build() {
    # Programs
    cd $BUILD_DIR
    if [ ! -d $BUILD_DIR/kas/.git ]; then
        git clone https://github.com/fdgonthier/kas.git
        [ $? -eq 0 ] || return 1
    else
        cd $BUILD_DIR/kas && git pull
        [ $? -eq 0 ] || return 1
    fi
    cd $BUILD_DIR/kas
    scons --quiet config \
        libktools_include=$TEAMBOX_HOME/include \
        libktools_lib=$TEAMBOX_HOME/lib \
        DBDIR=$TEAMBOX_HOME/share/teambox/db \
        DESTDIR=$TEAMBOX_HOME \
        CONFIG_PATH=$TEAMBOX_HOME/etc/ \
        PYTHONDIR=$TEAMBOX_HOME/share/teambox/python \
        WWWDIR=$TEAMBOX_HOME/www/ \
        VIRTUALENV=$TEAMBOX_HOME/share/teambox/virtualenv \
        BINDIR=bin
    [ $? -eq 0 ] || return 1

    scons --quiet build 
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
kas_debian_install() {
    cd $BUILD_DIR/kas

    scons --quiet install
    [ $? -eq 0 ] || return 1

    # PostgreSQL specific library
    mv -v $TEAMBOX_HOME/usr/lib/postgresql/9.1/lib/libkcdpg.so \
        /usr/lib/postgresql/9.1/lib/libkcdpg.so
    (cd $TEAMBOX_HOME && rmdir -v /usr/lib/postgresql/9.1/lib)

    # Init file.
    template init/kcd.debian.init.in /etc/init.d/kcd
    template init/kwsfetcher.debian.init.in /etc/init.d/kwsfetcher
    template init/kcdnotif.debian.init.in /etc/init.d/kcdnotif
    template init/kasmond.debian.init.in /etc/init.d/kasmond

    chmod -v +x \
        /etc/init.d/kcd \
        /etc/init.d/kwsfetcher \
        /etc/init.d/kasmond \
        /etc/init.d/kcdnotif
    update-rc.d kcd defaults

    # KFS directory.
    mkdir -p /var/cache/teambox/kfs
    mkdir -p /var/cache/teambox/kwsfetcher

    # We need to run ldconfig at this point because PostgreSQL will
    # try to load libkcdpg.so, which requires libktools.
    ldconfig

    return $?
}

dist="debian"
allModules="core tbxsosd kmod kas"
allSteps="init build install"

exec 2>&1 > teambox-installer.log

# Make sure the package library is updated.
echo "*** Updating package data." >&2
apt-get update

if [ "$dist" == "debian" -a -z "$(which killall)" ]; then
    apt-get install -y psmisc
fi

echo "*** Killing Teambox services" >&2
killall tbxsosd
killall kcd

# Generate SSL certificates for the sign-on service and
# the application service. Those are self-signed and can be 
# replaced if needed. The sign-on service SSL certificate
# are not currently used in the way the service is setup.
echo "*** Generating SSL keys" >&2
generate_ssl $TEAMBOX_HOME/etc/tbxsosd/ssl \
    tbxsosd.req tbxsosd.key tbxsosd.crt tbxsosd.cnf
generate_ssl $TEAMBOX_HOME/etc/kcd/ssl \
    kcd.req kcd.key kcd.crt kcd.cnf

make_directory

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
        echo -n "*** Executing ${currentModule}_${dist}_${currentStep}. " >&2
        ${currentModule}_${dist}_${currentStep}
        if [ $? -eq 1 ]; then
            echo "FAILED" >&2
            exit
        else
            echo "OK" >&2
        fi
    done
done

password_fix_all
configure_teambox

run_service tbxsosd
run_service kcd
run_service kcdnotif
run_service kwsfetcher
