#!/bin/tcsh
#
# DART software - Copyright UCAR. This open source software is provided
# by UCAR, "as is", without charge, subject to all terms of use at
# http://www.image.ucar.edu/DAReS/DART/DART_download
#
#set echo
########################################################################################
# Set up parameters that are used for other scripts throughout the cycling period.
# Note: 1. Specify a full path name at each line.
#       2. Namelist options should be specified for all Namelist files separately.  
########################################################################################
# General configuration 
#
set EXPERIMENT_NAME = may2019    # Change #

# PBS setup
set   RUN_IN_PBS = no           # Run on derecho using PBS? yes or no    # Change #
set  PROJ_NUMBER = /your_proj/	# Your account key for derecho  # Change #
set FILTER_NODES = 1            # Total no. of nodes for DART/filter (at least bigger than ensemble size)
set  MODEL_NODES = 1            # Total no. of nodes for MPAS/atmosphere_model 
set       N_CPUS = 36		# Number of cpus per node (default = 36)
set      N_PROCS = 16		# Number of mpi processors for MPAS (=> MODEL_NODES * N_PROCS for graph.info)
set N_PROCS_ANAL = 16		# Number of mpi processors for filter
set   QUEUE_MPAS = develop  	# queue for mpas
set     MEM_MPAS = 16           # memory for MPAS per node (GB) ; 240km ~ 8 GB
set    TIME_INIT = 00:50:00     # wall clock time for initial BKG forecast at PBS
set    TIME_MPAS = 00:10:00	# wall clock time for short forecast during DA at PBS
set  QUEUE_FILTER = develop  	# queue for filter
set   MEM_FILTER = 64           # memory for filter per node (GB)       ~ 12 GB
set  TIME_FILTER = 00:30:00	# wall clock time for mpi filter runs

set    HPSS_SAVE = no           # Backup in HPSS? yes or no. If yes, edit below.

# Ensemble configuration
set    MPAS_GRID = x1.10242  	# All grid parameters will be changed based on this.
set     ENS_SIZE = 10 	 	# Ensemble size
set     DT_MPAS  = 300    	# timestep for MPAS
set     LEN_DISP = 5000.        # Finest scale (not used for now)
set ADAPTIVE_INF = true         # adaptive_inflation - If true, this script only supports
                                # spatially-varying state space prior inflation.
                                # And you also need to edit inf_sd_initial, inf_damping,
                                # inf_lower_bound, and inf_sd_lower_bound in &filter_nml
set       CUTOFF = 0.10         # half-width localization radius
set         VLOC = 60000.       # half-width localization radius in height [meters] - will be mulplied by CUTOFF
set num_output_obs_members = 2    # output members in obs_seq.out
set num_output_state_members = 2  # output members in output states    
set binary_obs_seq = false      # binary or ascii obs_seq.final to produce
set DISTRIB_MEAN = false        # true for a large-memory job; false otherwise
set CONVERT_OBS  = true         # convert_all_obs_verticals_first = .true. in &assim_tools_nml
set CONVERT_STAT = false        # convert_all_state_verticals_first = .false. in &assim_tools_nml
                                
set     INFL_OUT = output_priorinf
set      INFL_IN = input_priorinf

set   SST_UPDATE = false
set   SST_FNAME  = ${MPAS_GRID}.sfc_update.nc

# First Guess (for cold-start runs and initial ensemble)
set EXT_DATA_TYPE = GFS         # EXTERNAL DATA TYPE : GFS or GFSENS(GEFS) 
                                # for GFS,  DART will be run to add perturbations to GFS 
                                # for GEFS, will use external data from GEFS ensemble
                                  
set        VTABLE = Vtable.${EXT_DATA_TYPE}
set   USE_RESTART = true        # true  : use Restart file at streams
                                # false : use invariant and da_state file at streams; not implmented yet
                                #         invariant stream is supported after v8.1.0? (will be updated later)

# Directories
set ENS_DIR      = member
set ROOT_DIR     = /your_workdir/       # Change #

#
set BASE_DIR     = ${ROOT_DIR}/${EXPERIMENT_NAME}
set OUTPUT_DIR   = ${BASE_DIR}/output                   # output directory
set CSH_DIR      = ${BASE_DIR}/scripts	                # shell scripts
set EXE_DIR      = ${BASE_DIR}/exec	                # MPAS-A DART executables
set RUN_DIR      = ${BASE_DIR}/rundir          		# Run MPAS/DART cycling (temporary)
set SST_DIR      = ${BASE_DIR}/sst			# sfc_update.nc
set OBS_DIR      = ${BASE_DIR}/obs            		# obs_seq.out
set INIT_DIR     = ${BASE_DIR}/init                     # initial ensemble ; restart won't require init
set TEMPLATE_DIR = ${BASE_DIR}/template			# static and ancillary data
set EXTM_DIR     = ${BASE_DIR}/extm			# external data location to be downloaed
set HPSS_DIR     = ${BASE_DIR}/${EXPERIMENT_NAME}/HPSS 			# hpss archives

set MPAS_DIR     = /your_srcdir/MPAS-Model       # Change #
set DART_DIR     = /your_srcdir/DART             # Change #
set WPS_DIR      = /your_srcdir/WPS              # Change #

# Namelist files
set NML_INIT     = namelist.init_atmosphere      # Namelist for init_atmosphere_model
set NML_MPAS     = namelist.atmosphere		 # Namelist for atmosphere_model
set NML_WPS      = namelist.wps			 # Namelist for WPS
set NML_DART     = input.nml			 # Namelist for DART
set STREAM_ATM   = streams.atmosphere		 # I/O list for atmosphere_model
set STREAM_INIT  = streams.init_atmosphere	 # I/O list for init_atmosphere_model

# Commands (do not need modification unless moving to new system)
set HSICMD = 'hsi put -P'
set REMOVE = '/bin/rm -rf'
set   COPY = 'cp -pf'
set   MOVE = 'mv -f'
set   LINK = 'ln -sf'
unalias cd
unalias ls
