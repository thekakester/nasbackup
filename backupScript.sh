#!/bin/bash
#################################################
# NETWORK BACKUP SCRIPT                         #
# Written by Mitch, 8/1/16                      #
# Backs up specified data to an external source #
#################################################

#################################################
# SETTINGS                                      #
#-----------------------------------------------#
# MOST settings must be in three separate files #
# in the same directory as this script.         #
# They are:                                     #
#     - usernameForBackup.txt                   #
#     - passwordForBackup.txt                   #
#     - backupSources.txt                       #
#                                               #
# Here is a brief description of what each file #
# must contain                                  #
#                                               #
# usernameForBackup.txt:                        #
#     - Contains EXACTLY one line, the username #
#       to use when connecting to the NAS       #
#       drives.  (All drives should have this   #
#       user set up)                            #
#                                               #
# passwordForBackup.txt:                        #
#     - Contains EXACTLY one line: the password #
#       See "usernameForBackup.txt"             #
#                                               #
# backupSources.txt:                            #
#     - List each source you want backed up on  #\
#       separate lines.  There should be no     #
#       empty lines and there should also be no #
#       lines containing information other than #
#       source folders. Example:                #
#           +---+----------------------+        #
#           | 1 | //nas4/info          |        #
#           | 2 | //nas2/process1      |        #
#           | 3 | //nas4/cnc           |        #
#           +---+----------------------+        #
#                                               #
# You may also change the variables below       #
#                                               #
#################################################

#Where to mount the media to.  This is a temporary folder
MOUNT_FOLDER="/media/temp_mount"

#Where to save the backup to.  This must be a local folder!  Mount a network drive if you must
DESTINATION="/run/media/duncan/backup1/"

#Where to store output in a log file
LOG_FILE="/home/duncan/Desktop/backupLog.txt"

#What is the location of this file?  We need to CD to it so we can find the settings files!
#Must be an absolute path (starting with "/")
RUN_FROM="/home/duncan/Desktop"
#################################################
# MAIN PROGRAM                                  #
# DO NOT MODIFY BELOW THIS POINT                #
#################################################
DEF="\e[0m"
CYN="\e[96m"
YEL="\e[93m"
RED="\e[31m"

function unmountDirectory {
	if mount|grep -q $MOUNT_FOLDER; then
		echo "Unmounting $MOUNT_FOLDER"
		sudo umount -f $MOUNT_FOLDER
	fi
}

#Prints a blue divider
function printDivider {
	COL=$(tput cols)
	echo -en $CYN;
	printf '=%.0s' $(seq 1 $COL)
	echo -e $DEF;
}

if [[ $(/usr/bin/id -u) -ne 0 ]]; then
    echo "You must be running as root to run this script"
    exit
fi

clear

#CD to the right directory
cd $RUN_FROM

#Log that we started
echo "$(date) Started backup" >> $LOG_FILE

#Get the username and password for the backup
read NASUSER < usernameForBackup.txt
read NASPASS < passwordForBackup.txt

#Read in the sources to back up
echo -e "${CYN}Preparing to back up:$DEF"
SOURCES=()
while read -r line; do
	echo -e "  - ${YEL}$line$DEF"
	SOURCES+=($line)
done < backupSources.txt


for i in ${!SOURCES[@]}; do
	SOURCE=${SOURCES[$i]}
	
	#log progress
	echo "$(date)     $SOURCE" >> $LOG_FILE	

	printDivider
	echo -e ${CYN}Backing up ${YEL}$SOURCE
	printDivider	

	#Create the directory if it doesn't exist already
	if [ ! -d "$MOUNT_FOLDER" ]; then
		echo "Creating directory $MOUNT_FOLDER because it doesn't exist"
		sudo mkdir $MOUNT_FOLDER
	fi

	#Unmount MOUNT_FOLDER if something is already mounted to it
	unmountDirectory

	#Actually mount up the drive now.  -t cifs means type=cifs (some network fs)
	echo "Mounting $SOURCE to $MOUNT_FOLDER"
	sudo mount -t cifs $SOURCE $MOUNT_FOLDER -o user="$NASUSER",password="$NASPASS" >> $LOG_FILE

	#Before we start rsync, make sure our backup folder exists
	#Relative_folder = $i, but replace "//" with ""
	RELATIVE_FOLDER=${SOURCE/\/\//}
	BACKUP_FOLDER=${DESTINATION}/$RELATIVE_FOLDER
	if [ ! -d "$BACKUP_FOLDER" ]; then
		echo "Creating directory $BACKUP_FOLDER because it doesn't exist"
		sudo mkdir -p $BACKUP_FOLDER >> $LOG_FILE
	fi

	#There was a little bug where if you interrupted the mount,
	#rsync would think there were no files in the MOUNT_FOLDER
	#and it would start deleting from the backup
	#We can do a check first by making sure the mount succeeded
	echo $NASUSER >> $LOG_FILE
	if mount|grep -q $MOUNT_FOLDER; then

		#Sync the folders
		#a & r = recursive
		#t = Preserve timestamps
		#z = compress
		#v = verbose
		#delete = Delete files that no longer exist on source
		echo "Syncing... This may take a while"
		echo "Syncing folder $SOURCE to $BACKUP_FOLDER"
		sudo rsync -artzv --delete $MOUNT_FOLDER/ $BACKUP_FOLDER
		
	else
		echo -e "${RED}ERROR: Can't back up${DEF}: Drive mounting failed"
		echo -e "$(date)          FAILED: Drive not mounted" >> $LOG_FILE
	fi

	#Unmount now that we're done
	unmountDirectory

	#New lines for formatting
	echo ""
	echo ""
done

printDivider
printDivider
printDivider
echo -e ""
echo -e ${CYN}All backups are complete${DEF}
echo -e "$(date) Backup complete\n\n" >> $LOG_FILE
