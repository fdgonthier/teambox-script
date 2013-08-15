# Teambox Installer Script

This is the installer script for the Teambox collaboration system on a single computer.

## Requirements

- A `bare` Linux machine running one of the following distribution: Debian 7.x, Ubuntu 12.04, CentOS 6.4
- A Windows computer running the classic Teambox client.

## Server install

It is highly recommended that this gets installed on a server machine, and OpenVZ container, or a virtual machine, on which no other software is installed. The installer will install several components which may conflict with components already installed or that at least will increase the resource pressure on what is currently installed.

To install Teambox simply fetch the script corresponding to the Teambox version you want to install (R2 is the current version at the time I'm writing this) and run it. This is a Bash script who will be very verbose.

The following major components are installed:

- PostgreSQL 9.1
- Apache 2
- Teambox Core libraries
- Teambox Sign-On Server (tbxsosd)
- Teambox Collaboration Server (kas)

## How to install

<pre>
$ wget "https://raw.github.com/fdgonthier/teambox-script/master/teambox-installer.sh"
$ chmod +x ./teambox-installer.sh
$ ./teambox-installer.sh
</pre>

On a compatible system, this should be enough to get Teambox working. If you see an error message, please re-run the script by redirecting the output.

<pre>
$ ./teambox-installer.sh > teambox-installer.log
</pre>

Analyse the output or report a bug along with it. Another useful debugging tool is running the scrip with Bash in verbose mode.

<pre>
$ bash -x teambox-installer.sh > teambox-installer.log
</pre>

This will give you a preview of all the commands that were executed while the script is running.

### Command line arguments

- `--keep`: Preserves the build directory in /tmp.
- `--use-head`: Use the tip of all the repositories instead of a specific release tag.
- `--fdg`: Fetch the Teambox repositories from http://github.com/fdgonthier instead of http://github.com/tmbx. The repositories by yours truly might be more current than those merged in the tmbx group, but it comes at the cost of stabilitiy.

## Ubuntu

Ubuntu is not the preferred distribution of Teambox but, starting Ubuntu 12.04, it is similar enough to Debian Wheezy to require no special handling in the script. Teambox should work as well on Ubuntu as on Debian.

## CentOS: A note of caution

Even though Teambox is native of the Debian platform, supporting CentOS felt important for me due to its closeness to the RHEL commercial product which is used by many companies. CentOS is also a very stable product which is support on a long term basis.

The code supporting CentOS install has not been extensively tested but I have verified that all components were properly installed and working. This software is not developped and tested for CentOS so this specfic distribution might display bug which is not present in Debian derivative distributions.

### Third party repositories

From a clean CentOS install, the following Yum repositories are added:

- The PostgreSQL Yum repository (for PostgreSQL 9.1): http://yum.postgresql.org/9.1
- RPM Forge (for the ADNS library): http://packages.sw.be/rpmforge-release
- EPEL

All of those repositories are installed to paliate packages required by Teambox but missing from the main distribution. EPEL (Extra Packages for Enterprise Linux) is usually not seen as third party but I cannot judge of the reliability of the other packages that are installed.

The script will blindly install the package whether or not the components are already present on the system. That means that it will ignore self-installed packages and self-compiled packages.

# Other notes

- The KAS collaboration server requires access to the guts of PostgreSQL, so this will never work with MySQL. Don't ask.