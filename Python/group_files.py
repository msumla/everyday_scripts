# Introduction: this script might come in handy whenever you have multiple
# folders with a bunch of files in them which you would like to group into one
# folder (e.g. downloaded movies or music which all came in many folders, but
# You would like have them all in one folder and cut-paste would take ages.
# Usage: run the script in a Linux command line interface (bash, terminal) or
# Windows 10's Linux bash subsystem as: python PATH_TO_THE_SCRIPT/group_files.py
# in the folder where you would like to group those files together or add
# the path of the folder in the end of the command as an argument:
# python PATH_TO_THE_SCRIPT/group_files.py PATH_TO_THE_FOLDEER.
# P.S. Files with identical names are treated, _n is added (n as number).

from os.path import exists
import os, sys, shutil

try:
    path = sys.argv[1]
except:
    path = './'
try:
    ext = sys.argv[1]
except:
    ext = 'srt'
#try:
#	sim = sys.argv[1]
#except:
#	sim = shutil.move
dirs = os.listdir(path)
q = input('Are you sure? (y/n)\n').upper()
c = 2

if q == 'Y' or q == 'YES':
    for dir in dirs:
        if os.path.isdir(dir):
            for file in os.listdir(dir):
                if file.endswith('mkv') or file.endswith('mp4') or file.endswith('avi') or file.endswith('mp3') or file.endswith(ext):
                    if not exists(path + file):
                        shutil.move(path + dir + '/' + file, path + file)
                        print('Moved file from ' + path + dir + '/' + file + ' to ' + path + file)
                    else:
                        shutil.move(path + dir + '/' + file, path + file[:len(str(file))-4] + '_' + str(c) + file[len(str(file))-4:])
                        print('Moved file from ' + path + dir + '/' + file + ' to ' + path + file[:len(str(file))-4] + '_' + str(c) + file[len(str(file))-4:])
                        c += 1
            shutil.rmtree(path + '/' + dir, ignore_errors=True)
            print('Deleted directory ' + path + dir)
            print('')
else:
    print('Exit')
