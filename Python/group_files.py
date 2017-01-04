# Introduction: this script might come in handy whenever you have multiple
# folders with a bunch of files in them which you would like to group into one
# folder (e.g. downloaded movies or music which all came in many folders, but
# You would like have them all in one folder and cut-paste would take ages.
# Usage: run the script in a Linux command line interface (bash, terminal) or
# Windows 10's Linux bash subsystem as: python PATH_TO_THE_SCRIPT/group_files.py
# in the folder where you would like to group those files together.
# P.S. Files with identical names are treated, _n is added (n as number).

from os.path import exists
import os, shutil

path = './'
dirs = os.listdir(path)
q = raw_input('Are you sure? (y/n)\n').upper()
c = 2

if q == 'Y' or q == 'YES':
	for dir in dirs:
		for file in os.listdir(dir):
			if not exists(path + file):
				shutil.move(path + dir + '/' + file, path + file)
				print 'Moved file from ' + path + dir + '/' + file + ' to ' + path + file
			else:
				shutil.move(path + dir + '/' + file, path + file + '_' + str(c))
				print 'Moved file from ' + path + dir + '/' + file + ' to ' + path + file + '_' + str(c)
				c += 1
			print ''
		shutil.rmtree(path + '/' + dir, ignore_errors=True)
		print 'Deleted directory ' + path + dir
else:
	print 'Exit'
