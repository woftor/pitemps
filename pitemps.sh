#!/bin/bash
#
# ++++ Raspberry Pi Temperature script ++++
#
# By woftor (GitHub)
#
# This script shows the temperature of the ARM CPU of you Raspberry Pi: current, mean, lowest and highest.
# You can choose between Celcius of Fahrenheit.
# It uses three text files to store data:
#   - pitemps_file for the last temperatures
#   - pitemps_data_file_mean to calculate a mean temperature
#   - pitemps_data_file_plot for plotting/arhiving
#
# You can tweak the update interval and the number of hours to use for the mean.
# Other variables are in the first part of this script.
#
# To make a plot, see the configuration file 'pitemps-gnuplot.conf'
#
# ---- ---- ---- ---- ---- Change variables below this line ---- ---- ---- ---- ----

# Update time in seconds
#  Note: the script will finish the whole duration of update time at exit. Make it too long and the waiting time on exit can be long
#  CTRL-C is disabled ny default. You can enable it by commenting out "trap '' 2" below
#  Doing a CTRL-C will disable output to the file with last temperatures however
update_interval=4

# Number of hours to use for the mean.
no_hours_mean=1

# Number of hours to store for plotting/archiving (the data older than this will be deleted)
no_hours_plot=168

# Which directory to use to store the files (must be writable, will be created if necessary)
pitemps_dir=~/pitemps

# Name of the file containing the last temperatures (mean, high and low)
pitemps_file=pitemps-last.txt

# Name of the data file containing the temperatures used for the mean
pitemps_data_file_mean=pitemps-data-mean.txt

# Name of the data file containing the temperatures for plotting/archiving
pitemps_data_file_plot=pitemps-data-plot.txt

# Make backups of data files if they exist? 1 for Yes and 2 for No
make_backups=1

# Date format (see 'man date' for help). Default %d-%m-%Y %H:%M:%S - 14-05-2017 20:48:23
date_format="%d-%m-%Y %H:%M:%S"

# Temperature scale: 1 for degree Celcius, 2 for degree Fahrenheit
temp_scale=1

# Trap 'signal 2' to disable CTRL-C
#  CTRL-C is disabled ny default. You can enable it by commenting out this variable
#  Doing a "CTRL-C" will disable output to the file with last temperatures however
trap '' 2

# ---- ---- ----  ---- ---- Change variables above this line ---- ---- ---- ---- ----

# Official version. Please don't change.
version=2.2.1

# ---- ---- ----  ---- ---- Begin of variable check section  ---- ---- ---- ---- ----

# Check if 'bc' installed? (required)
command -v bc >/dev/null 2>&1 || { echo; echo >&2 "Error: program 'bc' is not installed, please install it ('sudo apt install bc')"; echo; exit 1; }

# Check if the update time is valid (must be an integer)
re='^[0-9]+$'
if ! [[ $update_interval =~ $re ]]
then
    echo
    echo "Error: Number of seconds update time must be an integer (1,2,3 etc.). It is now set to '$update_interval'. Please check variables in pitemps file."
    echo
    exit 1
fi

# Check if the number of hours for the mean is valid (must be an integer)
if ! [[ $no_hours_mean =~ $re ]]
then
    echo
    echo "Error: Number of hours to use for mean must be an integer (1,2,3 etc.). It is now set to '$no_hours_mean'. Please check variables in pitemps file."
    echo
    exit 1
fi

# Check if the option to make backups is valid
if  [[ $make_backups != 1 && $make_backups != 2 ]]
then
    echo
    echo "Error: Option to make backups must be 1 (Yes) or 2 (No). It is now set to '$make_backups'. Please check variables in pitemps file."
    echo
    exit 1
fi

# Check if the temperature scale is valid
if  [[ $temp_scale != 1 && $temp_scale != 2 ]]
then
    echo
    echo "Error: Temperature scale must be 1 (Celcius) or 2 (Fahrenheit). It is now set to '$temp_scale'. Please check variables in pitemps file."
    echo
    exit 1
fi

# Check if the directory to store the files exists and if it's writable
if [[ ! -d $pitemps_dir ]]
then
    if [[ -w $(dirname "$pitemps_dir") ]]
    then
        mkdir $pitemps_dir
    else
        echo
        echo "Error: Cannot create pitemps directory '$pitemps_dir' - No write permission. Please check variables in pitemps file."
        echo
    exit 1
    fi
else
    if [[ ! -w $pitemps_dir ]]
    then
        echo
        echo "Error: No write permissions in pitemps directory '$pitemps_dir'. Please check variables in pitemps file."
        echo
    exit 1
    fi
fi

# Max hours 9999
if [[ $no_hours_mean -gt 9999 ]]
then
    echo
    echo "Error: Too many hours for calculation mean (max 9999). It is now set to '$no_hours_mean'. Please check variables in pitemps file."
    echo
    exit 1
fi

# ---- ---- ----  ---- ---- End of variable check section  ---- ---- ---- ---- ----


# This is to make sure the file containing the last variables looks pretty (adds spaces if appropriate)
if [[ $no_hours_mean -gt 999 ]]
then
    spaces="    "
elif [[ $no_hours_mean -gt 99 ]]
then
    spaces="  "
elif [[ $no_hours_mean -gt 9 ]]
then
    spaces=" "
else
    spaces=""
fi

# Define function to make the temperatures read by the script human readable and do Fahrenheit converion if appropriate
if [[ $temp_scale = 1 ]]
then
    function convert_temp {
        bc <<< "scale=1; $1/1000"
    }
else
    function convert_temp {
        bc <<< "scale=1; $1 * 1.8 / 1000 + 32"
    }
fi

# Celcius or Fahrenheit symbol
if [[ $temp_scale = 1 ]]
then
    deg=$'\xc2\xb0'C
    else
    deg=$'\xc2\xb0'F
fi

# Some variables to format the output on the screen
noform=$(tput sgr0)
form1=$(tput setaf 6)
form2=$(tput bold)$(tput setaf 3)
form3=$(tput bold)$(tput setaf 2)
form4=$(tput bold)$(tput setaf 1)

# Set the path of the files
pitemps_file_P=$pitemps_dir/$pitemps_file
pitemps_data_file_mean_P=$pitemps_dir/$pitemps_data_file_mean
pitemps_data_file_plot_P=$pitemps_dir/$pitemps_data_file_plot

# Initial (bogus) temperatures, will not be stored
if [[ $temp_scale = 1 ]]
then
    low_temp=100.0
    high_temp=0.0
else
    low_temp=212.0
    high_temp=32.0
fi

# Initialize the text files (make backups if appropriate)
if [[ -f $pitemps_file_P ]]
then
    if [[ $make_backups = 1 ]]
    then
        if ! [[ -d $pitemps_dir/backups ]]
        then
            mkdir $pitemps_dir/backups
            cp --backup=t $pitemps_file_P $pitemps_dir/backups/$pitemps_file
        else
            cp --backup=t $pitemps_file_P $pitemps_dir/backups/$pitemps_file
        fi
    fi
    > $pitemps_file_P
else
    touch $pitemps_file_P
fi

if [[ -f $pitemps_data_file_mean_P ]]
then
    if [[ $make_backups = 1 ]]
    then
        if ! [[ -d $pitemps_dir/backups ]]
        then
            mkdir $pitemps_dir/backups
            cp --backup=t $pitemps_data_file_mean_P $pitemps_dir/backups/$pitemps_data_file_mean
        else
            cp --backup=t $pitemps_data_file_mean_P $pitemps_dir/backups/$pitemps_data_file_mean
        fi
    fi
    > $pitemps_data_file_mean_P
else
    touch $pitemps_data_file_mean_P
fi

if [[ -f $pitemps_data_file_plot_P ]]
then
    if [[ $make_backups = 1 ]]
    then
        if ! [[ -d $pitemps_dir/backups ]]
        then
            mkdir $pitemps_dir/backups
            cp --backup=t $pitemps_data_file_plot_P $pitemps_dir/backups/$pitemps_data_file_plot
        else
            cp --backup=t $pitemps_data_file_plot_P $pitemps_dir/backups/$pitemps_data_file_plot
        fi
    fi
    > $pitemps_data_file_plot_P
else
    touch $pitemps_data_file_plot_P
fi

# The time this script was started for the statistics
start_time_script=$(date +"$date_format")

# The time at beginning of the loop to calculate running time and when to truncate data file for mean and plotting/archiving
start_time_loop=$(date "+%s")

# Calculate when the data file for the mean and for plotting/archiving should be truncated
trunc_temp_data_mean=$(( $no_hours_mean * 3600 + $start_time_loop + $update_interval))
trunc_temp_data_plot=$(( $no_hours_plot * 3600 + $start_time_loop + $update_interval))

# Set stty for catching keys
if [[ -t 0 ]]
then
    stty -echo -icanon -icrnl time 0 min 0
fi

# Beginning of a loop to update temperatures and times
while true
do

    # Read the actual temperature from the sensor, make it human readable and do conversion to Fahrenheir if appropriate
    temp=$(convert_temp $(cat /sys/class/thermal/thermal_zone0/temp))

    # Check if the temperature is lower than the lowest recorded and change the variable if appropriate
    if (( $(bc <<< "$temp < $low_temp") ))
    then
        low_temp_time=$(date +"$date_format")
        low_temp=$temp
    fi

    # Check if the temperature is higher than the highest recorded and change the variable if appropriate
    if (( $(bc <<< "$temp > $high_temp") ))
    then
        high_temp_time=$(date +"$date_format")
        high_temp=$temp
    fi

    # The current time
    current_time=$(date +"$date_format")

    # The time during the loop to calculate running time
    current_time_loop=$(date "+%s")

    # Calculate the time the loop is running in seconds
    running_time=$(($current_time_loop-$start_time_loop))

    # Convert the running time of the script to human readable format
    running_time=$(echo "$((running_time / 86400)) day(s) $((($running_time % 86400) / 3600 )) hour(s) $((($running_time % 3600) / 60)) minute(s) $(($running_time % 60)) second(s)")

    # Write temperature and date/time to the data file for the mean and for plotting/archiving
    echo $current_time $temp | tee -a $pitemps_data_file_mean_P >> $pitemps_data_file_plot_P

    # Truncate the data file for the mean and for plotting/archiving if appropriate (from the top)
    if [[ $current_time_loop -gt $trunc_temp_data_mean ]]
    then
        sed -i '1d' $pitemps_data_file_mean_P
    fi

    if [[ $current_time_loop -gt $trunc_temp_data_plot ]]
    then
        sed -i '1d' $pitemps_data_file_plot_P
    fi

    # Calculate the mean temperature from the data file for the mean
    mean_temp=$(awk '{ total += $3 } END { printf"%.1f",total/NR }' $pitemps_data_file_mean_P)

    # Clear the screen
    clear

    # Present the temperatures / times
    echo "$(tput cup 2 6)$form1 ---- Raspberry Pi CPU Temperature ----$(tput cup 2 60)$noform v$version"

    echo "$(tput cup 4 2)$noform Current temperature:$(tput cup 4 40)| $form2$temp$noform $deg |"
    echo "$(tput cup 5 2)$noform Mean temperature - $no_hours_mean hour(s):$(tput cup 5 40)| $form2$mean_temp$noform $deg |"

    echo "$(tput cup 7 2)$noform Lowest temperature:$(tput cup 7 40)| $form3$low_temp$noform $deg | $form1($low_temp_time)"
    echo "$(tput cup 8 2)$noform Highest temperature:$(tput cup 8 40)| $form4$high_temp$noform $deg | $form1($high_temp_time)"

    echo "$(tput cup 10 6)$noform Update interval:$(tput cup 10 40)$form1$update_interval sec."
    echo "$(tput cup 11 6)$noform Script was started:$(tput cup 11 40)$form1$start_time_script"
    echo "$(tput cup 12 6)$noform Current date/time:$(tput cup 12 40)$form1$current_time"
    echo "$(tput cup 13 6)$noform Script is running:$(tput cup 13 40)$form1$running_time"

    echo "$(tput cup 16 2)$noform Press $form4'q'$noform to quit/exit..."

    echo "$(tput cup 18 5)$noform (Note: exit after max.$form1 $update_interval sec.$noform pressing 'q')"

    # Catch 'q' to quit. Then position cursur below the lowest line and break the loop
    read input
    if [[ "$input" = "q" ]]
    then
        tput cup 20 0
        break
    fi

    # Sleep for the duration of the update interval
    sleep $update_interval

done

# Set stty to normal again
if [[ -t 0 ]]
then
    stty sane
fi

# The time this script was stopped for the statistics
stop_time_script=$(date +"$date_format")

# Write the mean temperature to the file with the last temperatures
echo "Mean temperature - $no_hours_mean hour(s): $mean_temp $deg" >> $pitemps_file_P

# Write the lowest temperature to the file with the last temperatures
echo "Lowest temperature: $spaces          $low_temp $deg ($low_temp_time)" >> $pitemps_file_P

# Write the highest temperature to the file with the last temperatures
echo "Highest temperature: $spaces         $high_temp $deg ($high_temp_time)"  >> $pitemps_file_P

# Write the update interval, running time, start and stop times to the file with last temperatures
echo >> $pitemps_file_P
echo "Update interval:    $update_interval" >> $pitemps_file_P "sec."
echo "Script started:     $start_time_script" >> $pitemps_file_P
echo "Script stopped:     $stop_time_script" >> $pitemps_file_P
echo "Script was running: $running_time" >> $pitemps_file_P

# End signal 2 (CTRL-C) trap
trap 2
