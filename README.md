# Raspberry Pi Temperature script

By woftor (GitHub)

This script shows the temperature of the ARM CPU of you Raspberry Pi: current, mean, lowest and highest. You can choose between Celcius of Fahrenheit. It uses three text files to store data:

pitemps_file for the last temperatures
pitemps_data_file to calculate an mean temperature
pitemps_data_file_plot for plotting/arhiving
You can tweak the update interval (standard 4 secs) and the number of hours to use for the mean. Other variables are in the first part of this script.

To make a plot, see the configuration file 'pitemps-gnuplot.conf'
