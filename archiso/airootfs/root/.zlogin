# fix for screen readers
if grep -Fqa 'accessibility=' /proc/cmdline &> /dev/null; then
    setopt SINGLE_LINE_ZLE
fi

~/.automated_script.sh

# Menu do myarch so no primeiro console e so quando ninguem passou script= no boot
if [[ $(tty) == "/dev/tty1" ]] && ! grep -Fqa 'script=' /proc/cmdline; then
    myarch-menu
fi
