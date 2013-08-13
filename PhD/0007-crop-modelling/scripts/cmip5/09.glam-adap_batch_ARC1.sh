#!/bin/bash

#$ -l h_rt=02:00:00
#$ -l h_vmem=2G
#$ -l cputype=intel
#$ -cwd -V
#$ -m be

LIM_A=$1
GCM_ID=$2
EXP_ID=$3
#SCR_ID=$4

#get process id based on name of screen
#PID=`screen -list | grep ${SCR_ID} | cut -f1 -d'.' | sed 's/\W//g'`
PID=${LIM_A}_${GCM_ID}_${EXP_ID}
THOST="arc1"

#make processing directory if it doesnt exist
if [ ! -d "/nobackup/eejarv/workspace/cmip5_adap/process_${THOST}_${PID}" ]
then
	mkdir /nobackup/eejarv/workspace/cmip5_adap/process_${THOST}_${PID}
fi

cd /nobackup/eejarv/workspace/cmip5_adap/process_${THOST}_${PID}

#remove run script if it exists
if [ -f "run.R" ]
then
	rm -vf run.R
fi

#copy run file from local svn repo
cp -vf ~/Repositories/dapa-climate-change/trunk/PhD/0007-crop-modelling/scripts/cmip5/09.glam-adap_batch_ARC1.R run.R

#run R in batch for desired stuff
R CMD BATCH --vanilla --slave "--args lim_a=$LIM_A gcm_id=$GCM_ID exp_id=$EXP_ID" run.R /dev/tty

#remove processing directory again
cd /nobackup/eejarv/workspace/cmip5_adap
rm -rvf process_${THOST}_${PID}

