# fix for screen readers
if grep -Fqa 'accessibility=' /proc/cmdline &> /dev/null; then
    setopt SINGLE_LINE_ZLE
fi

sudo chown soaktest:soaktest /home/soaktest
sudo chmod 755 /home/soaktest/soak-test.sh
sudo chmod 755 /home/soaktest/test.sh
sudo chmod 755 /home/soaktest/summary.py

~/.automated_script.sh
