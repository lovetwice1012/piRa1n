#!/bin/sh
# Update the system and install dependencies
sys_updates_and_dependencies() {
  echo 'Updating the system and installing dependencies'
  apt-get update
  apt-get upgrade -y
  apt-get install -y git usbmuxd libimobiledevice6 libimobiledevice-utils \
  build-essential checkinstall git autoconf automake libtool-bin libreadline-dev \
  libusb-1.0-0-dev libusbmuxd-tools sshpass
}

# Compile libirecovery if not installed
compile_libirecovery() {
  if ! which irecovery >> /dev/null; then
    echo 'Compiling libirecovery'
    git clone 'https://github.com/libimobiledevice/libirecovery.git' /home/pi/libirecovery
    cd /home/pi/libirecovery/ || exit
    ./autogen.sh
    cd /home/pi/libirecovery/ || exit
    make
    make install
    ldconfig
    cd /home/pi/ || exit
    rm -rf libirecovery/
  fi
}

# Update piRa1n and piRa1n-web (if installed)
update_piRa1n() {
  # Update piRa1n-web if installed
  if [ -d /home/pi/piRa1n-web ]; then
    echo 'Updating piRa1n-web'
    git clone 'https://github.com/raspberryenvoie/piRa1n-web.git' /home/pi/tmp_piRa1n-web/
    find /home/pi/piRa1n-web -mindepth 1 -maxdepth 1 -not -name 'update.out' -exec rm -rf {} +
    # Use find to move .git/ too
    find /home/pi/tmp_piRa1n-web/ -mindepth 1 -maxdepth 1 -exec mv {} /home/pi/piRa1n-web/ \;
    rm -rf /home/pi/tmp_piRa1n-web/
    # Overwrite /var/www/html/ with new files
    rm -rf /var/www/html/*
    cp -R /home/pi/piRa1n-web/html/* /var/www/html/

    # Remove old sudoers lines and add new ones
    if grep -q 'piRa1n' /etc/sudoers; then
      temp_sudoers="$(mktemp)"
      cat /etc/sudoers > "$temp_sudoers"
      sed -i '/piRa1n/d' "$temp_sudoers"
      if visudo -qcf "$temp_sudoers"; then
        cat "$temp_sudoers" > /etc/sudoers
      else
        echo 'Failed to remove the old sudoers lines!'
      fi
      rm -f "$temp_sudoers"
    fi
    # Add new sudoers file
    (
      cd /tmp/ || exit
      echo '# piRa1n-web' > piRa1n-web
      echo 'www-data ALL=(ALL) NOPASSWD: /home/pi/piRa1n/piRa1n'
      sudo chown root:root piRa1n-web
      chmod 440 piRa1n-web
      if visudo -qcf piRa1n-web; then
        mv piRa1n-web /etc/sudoers.d/
      else
        echo 'Failed to add the sudoers file!'
      fi
      rm -f piRa1n-web
    )
  fi

  echo 'Updating piRa1n'
  [ -f /home/pi/piRa1n/piRa1n.conf ] && { mv /home/pi/piRa1n/piRa1n.conf /tmp/; piRa1n_config='1'; }
  rm -rf  /home/pi/piRa1n/
  git clone 'https://github.com/raspberryenvoie/piRa1n.git'  /home/pi/piRa1n/
  # Put back piRa1n.conf
  [ $piRa1n_config = '1' ] && mv /tmp/piRa1n.conf /home/pi/piRa1n/

  echo 'Creating a file with version of checkra1n'
  (
    cd /home/pi/piRa1n/ || exit
    ./checkra1n --version > checkra1n_version 2>&1
    # Keep only second line
    sed -i -n -e 2p checkra1n_version
    # Remove '# '
    sed -i 's/# //g' checkra1n_version
    # Lower case
    sed -i 's/\(.*\)/\L\1/' checkra1n_version
  )

  echo 'Fixing permissions'
  chown -R pi:pi /home/pi/piRa1n*/
  chmod -R 755 /home/pi/piRa1n*/
}

enable_at_startup() {
  echo 'Enabling piRa1n at startup'
  rm -f /lib/systemd/system/piRa1n.service
  cat << EOF > /etc/systemd/system/piRa1n.service
[Unit]
Description=piRa1n
After=multi-user.target

[Service]
ExecStart=/home/pi/piRa1n/startup.sh

[Install]
WantedBy=multi-user.target
EOF
  chmod 644 /etc/systemd/system/piRa1n.service
  systemctl daemon-reload
  systemctl enable piRa1n.service
  systemctl start piRa1n.service
}

# Update if internet is availble
if wget -q -T 0.5 -t 1 --spider 'https://duckduckgo.com'; then
  systemctl stop piRa1n.service

  echo '[1/3] Updating the system and installing dependencies...'
  sys_updates_and_dependencies > /var/log/piRa1n_updates.log 2>&1 || { echo 'Failed to install dependencies/update the system. See /var/log/piRa1n_updates.log for more info.'; exit 1; }
  compile_libirecovery >> /var/log/piRa1n_updates.log 2>&1 || { echo 'Failed to compile libirecovery. See /var/log/piRa1n_updates.log for more info.'; exit 1; }

  echo '[2/3] Updating piRa1n, piRa1n-web (if installed) and checkra1n...'
  update_piRa1n >> /var/log/piRa1n_updates.log 2>&1 || { echo 'Failed to update piRa1n and piRa1n-web (if installed). See /var/log/piRa1n_updates.log for more info.'; exit 1; }

  echo '[3/3] Enabling piRa1n at startup...'
  enable_at_startup >> /var/log/piRa1n_updates.log 2>&1 || { echo 'Failed to enable piRa1n at startup. See /var/log/piRa1n_updates.log for more info.'; exit 1; }
  cat << EOF
All done!

What's new ?
  piRa1n:
    - Made all scripts POSIX compliant
    - Switched from Bash to Dash because it's roughly 4x times faster according to the ArchWiki (sh is a symlink to Dash on Debian)
    - Cleaned up a lot of code
    - Fixed odysseyra1n option
EOF
  if [ -d /home/pi/piRa1n-web ]; then
  cat << EOF
  piRa1n-web:
    - Made install script POSIX compliant
    - Updated odysseyra1n instructions
EOF
  fi
else
  echo 'Cannot update. Check your network connection.'
fi
