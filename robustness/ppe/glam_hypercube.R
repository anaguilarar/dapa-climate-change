#Julian Ramirez-Villegas
#UoL / CCAFS / CIAT
#Apr 2014
#stop("!")

#outline
#1. load list of parameters
#2. create sample of parameter sets
#3. store the matrix of combinations as a data.frame
#4. put a given line into a parameter set
#5. use this parameter set for a model run

#src.dir <- "~/Repositories/dapa-climate-change/trunk/robustness"
#source(paste(src.dir,"/ppe/glam_hypercube.R",sep=""))

#load packages
library(lhs)

#source functions and stuff
src.dir <- "~/Repositories/dapa-climate-change/trunk/robustness"
source(paste(src.dir,"/glam-utils/make_dirs.R",sep=""))
source(paste(src.dir,"/glam-utils/make_soilfiles.R",sep=""))
source(paste(src.dir,"/glam-utils/make_sowfile.R",sep=""))
source(paste(src.dir,"/glam-utils/make_wth.R",sep=""))
source(paste(src.dir,"/glam-utils/make_parameterset.R",sep=""))
source(paste(src.dir,"/glam-utils/get_parameterset.R",sep=""))
source(paste(src.dir,"/glam-utils/run_glam.R",sep=""))
source(paste(src.dir,"/glam-utils/calibrate.R",sep=""))
source(paste(src.dir,"/meteo/extract_weather.R",sep=""))
source(paste(src.dir,"/ppe/put_param_hyp.R",sep=""))

#input directories
#wd <- "~/Leeds-work/quest-for-robustness"
wd <- "/nfs/a101/earjr/quest-for-robustness"
runs_dir <- paste(wd,"/crop_model_runs",sep="")
mdata_dir <- paste(wd,"/data/model_data",sep="")
bin_dir <- paste(wd,"/bin/glam-maize-c",sep="")
met_dir <- paste(wd,"/data/meteorology",sep="")
hyp_dir <- paste(runs_dir,"/glam_hypercube",sep="")
if (!file.exists(hyp_dir)) {dir.create(hyp_dir)}

#load objects (initial conditions and yields)
load(paste(mdata_dir,"/initial_conditions_major.RData",sep=""))
load(paste(mdata_dir,"/yield_major.RData",sep=""))

#select ME and its corresponding initial data
me_list <- unique(xy_main$ME_NEW)
me_sel <- me_list[1]
xy_me <- xy_main[which(xy_main$ME_NEW == me_sel),]

#me-specific dir
me_hdir <- paste(hyp_dir,"/run_me-",me_sel,sep="")
if (!file.exists(me_hdir)) {dir.create(me_hdir)}

#ensure SAT is not below DUL
corr_loc <- xy_me$LOC[which(round(xy_me$SAT,2) <= round(xy_me$DUL,2))]
corr_fac <- mean((xy_me$SAT[-which(round(xy_me$SAT,2) <= round(xy_me$DUL,2))]-xy_me$DUL[-which(round(xy_me$SAT,2) <= round(xy_me$DUL,2))]),na.rm=T)
xy_me$SAT[which(xy_me$LOC %in% corr_loc)] <- xy_me$DUL[which(xy_me$LOC %in% corr_loc)] + corr_fac
xy_main$SAT[which(xy_main$LOC %in% corr_loc)] <- xy_me$SAT[which(xy_me$LOC %in% corr_loc)]

###
#1. load list of parameters and ranges (./data/model_data/parameter_list.txt)
param_list <- read.csv(paste(mdata_dir,"/parameter_list_glam_lhs.txt",sep=""),sep="\t",header=T)

#2. create sample of parameter sets
#n=number of points (i.e. replicas) --how many values in each dimension?
#k=number of dimensions (i.e. parameters) --how many dimensions (i.e. parameters)?
nrep <- 10000
set.seed(2303)
if (!file.exists(paste(mdata_dir,"/glam_lhs.RData",sep=""))) {
  lhyp1 <- maximinLHS(n=nrep,k=nrow(param_list),dup=1)
  save(list=c("lhyp1"),file=paste(mdata_dir,"/glam_lhs.RData",sep=""))
} else {
  load(file=paste(mdata_dir,"/glam_lhs.RData",sep=""))
}

#3. generate the values in the actual parameter range and put into data.frame
out_df <- as.data.frame(matrix(NA, nrow=nrep, ncol=nrow(param_list)))
names(out_df) <- param_list$PARAM
for (i in 1:nrow(param_list)) {
  #i <- 1
  pvals <- qunif(lhyp1[,i],min=param_list$MIN[i],max=param_list$MAX[i])
  out_df[,i] <- pvals
}

#because snow has a limit in number of workers, i decided to drive using two different machines
driver <- Sys.info()[["nodename"]]
if (driver == "eljefe") {
  socket_list <- c(rep("localhost",30),rep("foe-linux-01",20),rep("foe-linux-02",20))
  hrun_list <- 1:(nrow(out_df)/2)
} else if (driver == "lajefa") {
  socket_list <- c(rep("localhost",30),rep("foe-linux-03",20),rep("foe-linux-04",20))
  hrun_list <- (nrow(out_df)/2+1):nrow(out_df)
}

#full list of locations
loc_list <- xy_me$LOC

###
#Note: from here onwards the process can be parallelised
#4. get a given line into a parameter set
for (hrun in hrun_list) {
  #hrun <- 1
  cat("\n------------------------------------\n")
  cat("\n...processing hypercube run=",hrun,"\n")
  cat("\n------------------------------------\n")
  
  #get parameter set
  base_params <- GLAM_get_default(mdata_dir)
  hyp_params <- put_param_hyp(out_df[hrun,], params=base_params, p_list=names(out_df), all_param=param_list)
  
  #create hrun dir
  out_hdir <- paste(me_hdir,"/calib_",hrun,sep="")
  if (!file.exists(out_hdir)) {dir.create(out_hdir)}
  
  #check what has been done already
  loc_sel <- loc_list
  for (tloc in loc_list) {
    #tloc <- loc_list[1]
    save_file <- paste(out_hdir,"/calib-",hrun,"_loc-",tloc,".RData",sep="")
    if (file.exists(save_file)) {loc_sel <- loc_sel[-which(loc_sel == tloc)]}
  }
  
  #create meteorology
  if (hrun == 1) {
    for (tloc in loc_sel) {
      cat("...creating meteo for loc=",tloc,"\n")
      #create meteorology for selected grid cells
      wval <- extract_weather(cellid=tloc, lon=xy_me$x[which(xy_me$LOC == tloc)], 
                              lat=xy_me$y[which(xy_me$LOC == tloc)], met_dir=met_dir, 
                              data_type="obs", dataset="WFD", sce="hist", years=1950:2001,ow=F)
    }
  }
  
  #5. use this parameter set to calibrate the model for all locations in parallel
  run_hyp_loc <- function(iloc) {
    if (driver %in% c("eljefe","lajefa")) {system("renice 19 -u earjr",ignore.stdout=T)}
    
    #source all needed functions
    source(paste(src.dir,"/glam-utils/make_dirs.R",sep=""))
    source(paste(src.dir,"/glam-utils/make_soilfiles.R",sep=""))
    source(paste(src.dir,"/glam-utils/make_sowfile.R",sep=""))
    source(paste(src.dir,"/glam-utils/make_wth.R",sep=""))
    source(paste(src.dir,"/glam-utils/make_parameterset.R",sep=""))
    source(paste(src.dir,"/glam-utils/get_parameterset.R",sep=""))
    source(paste(src.dir,"/glam-utils/run_glam.R",sep=""))
    source(paste(src.dir,"/glam-utils/calibrate.R",sep=""))
    source(paste(src.dir,"/meteo/extract_weather.R",sep=""))
    source(paste(src.dir,"/ppe/put_param_hyp.R",sep=""))
    
    #select location
    loc <- loc_sel[iloc]
    
    #arguments
    cal_data <- list()
    cal_data$CROP <- "maize"
    cal_data$MODEL <- "glam-maiz"
    cal_data$BASE_DIR <- out_hdir
    cal_data$BIN_DIR <- bin_dir
    cal_data$PAR_DIR <- mdata_dir
    cal_data$WTH_DIR <- paste(met_dir,"/ascii_extract_raw",sep="") #for reading .wth files
    cal_data$WTH_ROOT <- "obs_hist_WFD"
    cal_data$LOC <- loc
    cal_data$LON <- xy_me$x[which(xy_me$LOC == cal_data$LOC)]
    cal_data$LAT <- xy_me$y[which(xy_me$LOC == cal_data$LOC)]
    cal_data$ISYR <- 1981
    cal_data$IEYR <- 2000
    cal_data$INI_COND <- xy_main
    cal_data$YLD_DATA <- xy_main_yield
    cal_data$SIM_NAME <- paste("calib-",hrun,"_loc-",loc,sep="")
    cal_data$RUN_TYPE <- "RFD"
    cal_data$METHOD <- "RMSE"
    cal_data$USE_SCRATCH <- T
    cal_data$PARAMS <- hyp_params
    
    #scratch in /scratch or in /dev/shm
    if (driver %in% c("eljefe","lajefa")) {
      if (loc%%2 == 0) {
        cal_data$SCRATCH <- "/scratch/earjr"
      } else {
        cal_data$SCRATCH <- "/dev/shm/earjr"
      }
    } else {
      cal_data$SCRATCH <- "~/scratch/earjr"
    }
    
    if (!file.exists(paste(cal_data$BASE_DIR,"/",cal_data$SIM_NAME,".RData",sep=""))) {
    
      #create meteorology for selected grid cells
      wval <- extract_weather(cellid=cal_data$LOC, lon=cal_data$LON, lat=cal_data$LAT, met_dir=met_dir, 
                              data_type="obs", dataset="WFD", sce="hist", years=1950:2001,ow=F)
      
      #run calibration
      cal_data$PARAMS$glam_param.mod_mgt$IASCII <- 1 #output only to season file
      ygp_calib <- GLAM_calibrate(cal_data)
      
      #save output object
      save(ygp_calib, file=paste(cal_data$BASE_DIR,"/",cal_data$SIM_NAME,".RData",sep=""))
    }
    
    #remove junk / scratch as needed
    if (cal_data$USE_SCRATCH) {system(paste("rm -rf ",cal_data$SCRATCH,"/",cal_data$SIM_NAME,sep=""))}
    
    #return object
    rdata_fil <- paste(cal_data$BASE_DIR,"/",cal_data$SIM_NAME,".RData",sep="")
    return(rdata_fil)
  }
  
  
  #if there are param*seeds still not fully done then run the opt function in parallel
  if (length(loc_sel) > 0) {
    require(snowfall)
    
    #parallelisation
    sfInit(parallel=T,cpus=70,socketHosts=socket_list,type="SOCK")
    sfExport(list=c("loc_sel","bin_dir","mdata_dir","met_dir","xy_me","xy_main","xy_main_yield"))
    sfExport(list=c("me_sel","param_list","src.dir","me_hdir","out_hdir","wd","hyp_params"))
    sfExport(list=c("run_hyp_loc","driver","hrun"))
    run_steps <- sfSapply(as.vector(1:length(loc_sel)), run_hyp_loc)
    sfStop()
  }
}

