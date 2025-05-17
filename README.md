# NAME

pactl-loopmgt.pl - manage PulseAudio/Pipewire loop devices

# SYNOPSYS

- **pactl-loopmgt.pl**
\[**-h|--help**\]
\[**-m|--man**\]
\[**-f|--file**\]
\[**-t|--table**\]
\[**-j|--json**\]
\[**-d|--daemon**\]

# DESCRIPTION

This tool is a wrapper around "pactl". It can create and manage the input and
output of loop devices, manage the sound volume and manage defaults input and
output devices. It supports both USB and Bluetooth devices.

Some of the additional features of pactl-loopmgt.pl are:

- display the running configuration in a tabular
- export the running configuration in json
- apply the configuration saved in a json file
- handle multiple input/output per loopdevice (by priority order)
- daemon mode
- force volume settings

# OPTIONS

- **-h|--help**

    Print a brief help message and exit.

- **-m|--man**

    Print the full manual page and exit.

- **-f|file**

    JSON configuration file. A template can be generated with the option "--json".

- **-t|table**

    Print the running configuration in an extra large tabular.

- **-j|json**

    Generate a JSON configuration template based on the current running configuration.

- **-d|daemon**

    Do not exit after the first configuration but listen for any event in Pipewire.
    After each event the rules will be reevaluated.

# CAVEATS

- File format may slighly change in the future.

# EXAMPLES

## DAEMON

    pactl-loopmgt.pl -d -f config-file.json

# HOWTO

The simplest way to configure pactl-loopmgt.pl is to create the desired configuration using
an other tool (see ["SEE ALSO"](#see-also)). Then, use pactl-loopmgt.pl to save and recall the configuration:

    pactl-loopmgt.pl --json > config-file.json
    pactl-loopmgt.pl -d -f config-file.json

The JSON file must look like:

    {
        "loopback": {
            "loopback-3568-13": {
                "desc": "loopback-3568-13",
                "dst": [
                    "bluez_output.01_17_D1_AE_1E_7D.2",
                    "alsa_output.pci-0000_08_00.1.hdmi-stereo-extra1"
                ],
                "src": [
                    "alsa_input.pci-0000_0a_00.4.analog-stereo"
                ],
                "sinkId": 73512,
                "sourceId": 73513
            }
        },
        "nodes": {
            "alsa_output.pci-0000_08_00.1.hdmi-stereo-extra1": {
                "base_volume": "100%",
                "devId": 73540,
                "desc": "Monitor of Navi 31 HDMI/DP Audio Digital Stereo (HDMI 2)"
            },
            "alsa_input.pci-0000_0a_00.4.analog-stereo": {
                "devId": 27322,
                "desc": "Starship/Matisse HD Audio Controller",
                "base_volume": "10%"
            }
        },
        "def_input": "alsa_input.pci-0000_0a_00.4.analog-stereo",
        "def_output": "alsa_output.pci-0000_08_00.1.hdmi-stereo-extra1"
    }

- All device ids are kept for debuging and can be safely removed.
- Loopback "dst" and "src" attributes are JSON arrays.
    - The attribute is set to the first device found.
    - It can be used to automatically handle USB and Bluetooth device connection.
- If set, the "base\_volume" will be enforced.

# TODO List

- Manage **def\_input** and **def\_output** with arrays.
- Manage latency
- Manage sink\_input (client programs)
    - auto detection
    - patter matching on the name
    - volume
    - output devices

# COPYRIGHT

Permission to use, copy, modify, distribute, and sell this software and its
documentation for any purpose is hereby granted without fee, provided that
the above copyright notice appear in all copies and that both that
copyright notice and this permission notice appear in supporting
documentation.  No representations are made about the suitability of this
software for any purpose.  It is provided "as is" without express or
implied warranty.

# SEE ALSO

- [pavucontrol](https://freedesktop.org/software/pulseaudio/pavucontrol/)

    GTK based mixer for Pulseaudio and Pipewire.

- [wireplumber](https://gitlab.freedesktop.org/pipewire/wireplumber)

    Modular session / policy manager for PipeWire.

- wpctl

    Command line utility provided with Wireplumber.

- [pactl](https://www.freedesktop.org/wiki/Software/PulseAudio/)

    Command line tool from libpulse used has backend for this script.
