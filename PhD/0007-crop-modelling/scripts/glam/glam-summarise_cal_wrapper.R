#Julian Ramirez-Villegas
#UoL / CCAFS / CIAT
#June 2012


glam_summarise_cal_wrapper <- function(this_run) {
  #load required packages
  library(raster)
  
  #sourcing functions
  source(paste(src.dir,"/signals/climateSignals-functions.R",sep=""))
  
  #details of run
  sid <- runs_ref$SID[this_run]
  seed <- runs_ref$SEED[this_run]
  expID <- runs_ref$EXPID[this_run]
  
  #calibration folder
  runs_set <- paste("exp-",expID,sep="")
  cal_dir <- paste(cDir,"/calib/",runs_set,sep="")
  
  #load cell details
  cells <- read.csv(paste(cDir,"/inputs/calib-cells-selection-",selection,".csv",sep=""))
  
  #get the mask needed (to which data will be appended)
  ncFile <- paste(bDir,"/../climate-data/IND-TropMet_day/0_input_data/india_data.nc",sep="")
  ydDir <- paste(bDir,"/climate-signals-yield/GNUT/raster/gridded",sep="")
  
  metFile <- raster(ncFile,band=0)
  yldFile <- raster(paste(ydDir,"/raw/raw-66.asc",sep=""))
  msk <- maskCreate(metFile,yldFile)
  msk[] <- NA
  
  #method of yield detrending
  method <- "lin"
  
  #load irrigation rates
  irDir <- paste(cDir,"/irrigated_ratio",sep="")
  ir_stk <- stack(paste(irDir,"/raw-",1966:1993,".asc",sep=""))
  
  #select cell
  #cell <- cells$CELL[1]
  if (!file.exists(paste(cal_dir,"/calib_all_cells.csv",sep=""))) {
    # loop through gridcells
    for (cell in cells$CELL) {
      cat("\nprocessing gridcell",paste(cell),"\n")
      #get the required metrics:
      #1. mean predicted yield (taken from best value of YGP)
      #2. mean standard deviation of yield (taken from best value of YGP)
      #3. yield gap parameter
      #4. R pearson and pvalue
      #5. RMSE
      #6. RMSE / mean obs. yield * 100
      #7. initial planting date
      
      run_dir <- paste(cal_dir,"/fcal_",cell,sep="")
      ygpDir <- paste(run_dir,"/iter-ygp",sep="")
      sowDir <- paste(run_dir,"/iter-ipdate",sep="")
      
      #get best ygp, and mean predicted yield from that run
      #you need to read irrigated and rainfed, and also iratios
      cat("getting optimal ygp\n")
      load(paste(ygpDir,"/output.RData",sep=""))
      ygp <- optimal$YGP
      opt_pos <- which(optimised$YGP$VALUE == ygp)
      
      #load rainfed yields
      cat("load rainfed yields\n")
      data_dir <- paste(run_dir,"/iter-ygp/ygp/RFD_run-",opt_pos,"_",ygp,"/output",sep="")
      outfile <- list.files(data_dir,pattern="\\.out")
      pred <- read.table(paste(data_dir,"/",outfile,sep=""),header=F,sep="\t")
      names(pred) <- c("YEAR","LAT","LON","PLANTING_DATE","STG","RLV_M","LAI","YIELD","BMASS","SLA",
                       "HI","T_RAIN","SRAD_END","PESW","TRANS","ET","P_TRANS+P_EVAP","SWFAC","EVAP+TRANS",
                       "RUNOFF","T_RUNOFF","DTPUPTK","TP_UP","DRAIN","T_DRAIN","P_TRANS","TP_TRANS",
                       "T_EVAP","TP_EVAP","T_TRANS","RLA","RLA_NORM","RAIN_END","DSW","TRADABS",
                       "DUR","VPDTOT","TRADNET","TOTPP","TOTPP_HIT","TOTPP_WAT","TBARTOT")
      y_rfd <- pred$YIELD
      
      #load irrigated yields
      cat("load irrigated yields\n")
      data_dir <- paste(run_dir,"/iter-ygp/ygp/IRR_run-",opt_pos,"_",ygp,"/output",sep="")
      if (file.exists(data_dir)) {
        outfile <- list.files(data_dir,pattern="\\.out")
        pred <- read.table(paste(data_dir,"/",outfile,sep=""),header=F,sep="\t")
        names(pred) <- c("YEAR","LAT","LON","PLANTING_DATE","STG","RLV_M","LAI","YIELD","BMASS","SLA",
                         "HI","T_RAIN","SRAD_END","PESW","TRANS","ET","P_TRANS+P_EVAP","SWFAC","EVAP+TRANS",
                         "RUNOFF","T_RUNOFF","DTPUPTK","TP_UP","DRAIN","T_DRAIN","P_TRANS","TP_TRANS",
                         "T_EVAP","TP_EVAP","T_TRANS","RLA","RLA_NORM","RAIN_END","DSW","TRADABS",
                         "DUR","VPDTOT","TRADNET","TOTPP","TOTPP_HIT","TOTPP_WAT","TBARTOT")
        y_irr <- pred$YIELD
      } else {
        y_irr <- rep(0,times=length(y_rfd))
      }
      
      #get irrigation ratio
      #extract irrigation rates
      cat("get irrigation rates\n")
      ir_vls <- extract(ir_stk,cbind(X=cells$X[which(cells$CELL==cell)],Y=cells$Y[which(cells$CELL==cell)]))
      ir_vls <- as.numeric(ir_vls)
      ir_vls[which(ir_vls > 1)] <- 1
      
      #put all this into a data.frame
      cat("calculate 'true' predicted yield\n")
      y_pred <- data.frame(YEAR=1966:1993,RFD=y_rfd,IRR=y_irr,IRATIO=ir_vls)
      y_pred$PRED <- y_pred$RFD*(1-y_pred$IRATIO) + y_pred$IRR*y_pred$IRATIO
      
      #load observed yields
      cat("load observed yields\n")
      yfil <- paste(cDir,"/inputs/ascii/obs/yield_",cell,"_",method,".txt",sep="")
      y_o <- read.fortran(yfil,format=c("A12","F8"),n=28)
      y_pred$OBS <- y_o$V2
      
      #get anything -99 to NA
      y_pred$OBS[which(y_pred$OBS < -90)] <- NA
      
      #remove all lines that are NA in OBS and calculate 'n' (number of observations)
      y_pred <- y_pred[which(!is.na(y_pred$OBS)),]
      n <- nrow(y_pred)
      
      #4. R pearson and pvalue
      if (n >= 2) {
        cat("calculate final metrics\n")
        r_val <- cor.test(y_pred$PRED,y_pred$OBS)$estimate
        p_val <- cor.test(y_pred$PRED,y_pred$OBS)$p.value
      } else {
        r_val <- NA
        p_val <- NA
      }
      
      #5. RMSE
      rmse <- sqrt(sum((y_pred$OBS-y_pred$PRED)^2) / nrow(y_pred))
      
      #6. RMSE / mean obs. yield * 100
      prmse <- rmse/mean(y_pred$OBS)*100
      
      #mean and standard deviation of predicted and observed yield
      yp_mean <- mean(y_pred$PRED)
      yp_stdv <- sd(y_pred$PRED)
      yo_mean <- mean(y_pred$OBS)
      yo_stdv <- sd(y_pred$OBS)
      
      #remove optimal and optimised
      rm(optimal); rm(optimised)
      
      #get best initial planting date
      load(paste(sowDir,"/output.RData",sep=""))
      sow_date <- optimal$IPDATE
      
      #output data frame
      out_row <- data.frame(CELL=cell,X=cells$X[which(cells$CELL == cell)],
                            Y=cells$Y[which(cells$CELL == cell)],YGP=ygp,Y_OBS=yo_mean,YSD_OBS=yo_stdv,
                            Y_PRED=yp_mean,YSD_PRED=yp_stdv,CCOEF=r_val,PVAL=p_val,RMSE=rmse,P_RMSE=prmse,
                            SOW_DATE=sow_date,N=n)
      
      if (cell == cells$CELL[1]) {
        out_all <- out_row
      } else {
        out_all <- rbind(out_all,out_row)
      }
    }
    write.csv(out_all,paste(cal_dir,"/calib_all_cells.csv",sep=""),quote=T,row.names=F)
  } else {
    out_all <- read.csv(paste(cal_dir,"/calib_all_cells.csv",sep=""))
  }
  
  #now create the rasters
  out_rs_dir <- paste(cal_dir,"/calib_results_spat",sep="")
  if (!file.exists(out_rs_dir)) {dir.create(out_rs_dir)}
  
  rnames <- names(out_all)[4:13]
  for (rn in rnames) {
    if (!file.exists(paste(out_rs_dir,"/",tolower(rn),".asc",sep=""))) {
      cat("output of",rn,"\n")
      rs <- raster(msk)
      rs[out_all$CELL] <- out_all[,rn]
      rs <- writeRaster(rs,paste(out_rs_dir,"/",tolower(rn),".asc",sep=""),format="ascii",overwrite=T)
      rm(rs); g=gc(); rm(g)
    } else {
      cat(rn,"already exists\n")
    }
  }
  
  #ratio of observed to predicted mean yields
  if (!file.exists(paste(out_rs_dir,"/yobs_by_ypred.asc",sep=""))) {
    yo <- raster(paste(out_rs_dir,"/y_obs.asc",sep=""))
    yp <- raster(paste(out_rs_dir,"/y_pred.asc",sep=""))
    yo_yp <- yo/yp
    yo_yp <- writeRaster(yo_yp,paste(out_rs_dir,"/yobs_by_ypred.asc",sep=""),format="ascii",overwrite=T)
  } else {
    yo_yp <- raster(paste(out_rs_dir,"/yobs_by_ypred.asc",sep=""))
  }
  
  #ratio of observed to predicted sd yields
  if (!file.exists(paste(out_rs_dir,"/sdobs_by_sdpred.asc",sep=""))) {
    sdo <- raster(paste(out_rs_dir,"/ysd_obs.asc",sep=""))
    sdp <- raster(paste(out_rs_dir,"/ysd_pred.asc",sep=""))
    sdo_sdp <- sdo/sdp
    sdo_sdp <- writeRaster(sdo_sdp,paste(out_rs_dir,"/sdobs_by_sdpred.asc",sep=""),format="ascii",overwrite=T)
  } else {
    sdo_sdp <- raster(paste(out_rs_dir,"/sdobs_by_sdpred.asc",sep=""))
  }
  
  
  ### now plot the results
  if (plot_all) {
    #load required plotting libraries and data
    library(maptools); data(wrld_simpl)
    
    #check which cells do actually have less than .2 in AHRATIO
    cellNo <- cells$CELL[which(cells$AHRATIO<.2)]
    
    #plot ygp, scale 0 to 1
    rs <- raster(paste(out_rs_dir,"/ygp.asc",sep=""))
    if (length(cellNo) > 0) {
      rs[cellNo] <- NA
      xyNo <- xyFromCell(rs,cellNo)
      xyNo <- SpatialPoints(xyNo)
    }
    
    ht <- 1000
    fct <- (rs@extent@xmin-rs@extent@xmax)/(rs@extent@ymin-rs@extent@ymax)
    wt <- ht*(fct+.1)
    
    brks <- seq(0,1,length.out=21)
    brks.lab <- round(brks,2)
    cols <- c(colorRampPalette(c("red","orange","yellow","green","dark green"))(length(brks)))
    wld <- list("sp.polygons",wrld_simpl,lwd=0.8,first=F)
    
    if (length(cellNo) > 0) {
      pts1 <- list("sp.points", xyNo, pch = 4, col = "black", cex=0.75, lwd=0.75,first=F)
    }
    
    grat <- gridlines(wrld_simpl, easts=seq(-180,180,by=5), norths=seq(-90,90,by=5))
    grli <- list("sp.lines",grat,lwd=0.5,lty=2,first=F)
    
    #plot calibration points on top
    xycal <- cbind(x=cells$X[which(cells$ISSEL_F==1)],y=cells$Y[which(cells$ISSEL_F==1)])
    xycal <- SpatialPoints(xycal)
    pts2 <- list("sp.points", xycal, pch = 20, col = "black", cex=0.7, lwd=0.6,first=F)
    
    if (length(cellNo) > 0) {
      layt <- list(pts1,pts2,wld,grli)
    } else {
      layt <- list(pts2,wld,grli)
    }
    
    tiffName <- paste(out_rs_dir,"/ygp.tif",sep="")
    tiff(tiffName,res=300,compression="lzw",height=ht,width=wt)
    spplot(rs,sp.layout=layt,col.regions=cols,
           par.settings=list(fontsize=list(text=8)),
           at=brks,pretty=brks)
    dev.off()
    
    
    #plot y_obs and y_pred, scale should be set by both
    rso <- raster(paste(out_rs_dir,"/y_obs.asc",sep=""))
    if (length(cellNo) > 0) {rso[cellNo] <- NA}
    rsp <- raster(paste(out_rs_dir,"/y_pred.asc",sep=""))
    if (length(cellNo) > 0) {rsp[cellNo] <- NA}
    ht <- 1000
    fct <- (rso@extent@xmin-rso@extent@xmax)/(rso@extent@ymin-rso@extent@ymax)
    wt <- ht*(fct+.1)
    
    brks <- seq(min(rso[],rsp[],na.rm=T),max(rso[],rsp[],na.rm=T),length.out=20)
    brks.lab <- round(brks,1)
    cols <- c(colorRampPalette(c("green","yellow","orange","red"))(length(brks)))
    wld <- list("sp.polygons",wrld_simpl,lwd=0.8,first=F)
    grat <- gridlines(wrld_simpl, easts=seq(-180,180,by=5), norths=seq(-90,90,by=5))
    grli <- list("sp.lines",grat,lwd=0.5,lty=2,first=F)
    
    if (length(cellNo) > 0) {
      layt <- list(pts1,wld,grli)
    } else {
      layt <- list(wld,grli)
    }
    
    tiffName <- paste(out_rs_dir,"/y_obs.tif",sep="")
    tiff(tiffName,res=300,compression="lzw",height=ht,width=wt)
    spplot(rso,sp.layout=layt,col.regions=cols,
           par.settings=list(fontsize=list(text=8)),
           at=brks,pretty=brks)
    dev.off()
    
    tiffName <- paste(out_rs_dir,"/y_pred.tif",sep="")
    tiff(tiffName,res=300,compression="lzw",height=ht,width=wt)
    spplot(rsp,sp.layout=layt,col.regions=cols,
           par.settings=list(fontsize=list(text=8)),
           at=brks,pretty=brks)
    dev.off()
    
    
    
    #plot ysd_obs and ysd_pred, scale should be set by both
    rso <- raster(paste(out_rs_dir,"/ysd_obs.asc",sep=""))
    if (length(cellNo) > 0) {rso[cellNo] <- NA}
    rsp <- raster(paste(out_rs_dir,"/ysd_pred.asc",sep=""))
    if (length(cellNo) > 0) {rsp[cellNo] <- NA}
    ht <- 1000
    fct <- (rso@extent@xmin-rso@extent@xmax)/(rso@extent@ymin-rso@extent@ymax)
    wt <- ht*(fct+.1)
    
    brks <- seq(min(rso[],rsp[],na.rm=T),max(rso[],rsp[],na.rm=T),length.out=20)
    brks.lab <- round(brks,1)
    cols <- c(colorRampPalette(c("green","yellow","orange","red"))(length(brks)))
    wld <- list("sp.polygons",wrld_simpl,lwd=0.8,first=F)
    grat <- gridlines(wrld_simpl, easts=seq(-180,180,by=5), norths=seq(-90,90,by=5))
    grli <- list("sp.lines",grat,lwd=0.5,lty=2,first=F)
    
    if (length(cellNo) > 0) {
      layt <- list(pts1,wld,grli)
    } else {
      layt <- list(wld,grli)
    }
    
    tiffName <- paste(out_rs_dir,"/ysd_obs.tif",sep="")
    tiff(tiffName,res=300,compression="lzw",height=ht,width=wt)
    spplot(rso,sp.layout=layt,col.regions=cols,
           par.settings=list(fontsize=list(text=8)),
           at=brks,pretty=brks)
    dev.off()
    
    tiffName <- paste(out_rs_dir,"/ysd_pred.tif",sep="")
    tiff(tiffName,res=300,compression="lzw",height=ht,width=wt)
    spplot(rsp,sp.layout=layt,col.regions=cols,
           par.settings=list(fontsize=list(text=8)),
           at=brks,pretty=brks)
    dev.off()
    
    
    #ratio obs to pred yield
    ht <- 1000
    fct <- (yo_yp@extent@xmin-yo_yp@extent@xmax)/(yo_yp@extent@ymin-yo_yp@extent@ymax)
    wt <- ht*(fct+.1)
    
    brks <- seq(0,2,by=.2)
    brks.lab <- round(brks,2)
    rs <- yo_yp
    if (length(cellNo) > 0) {rs[cellNo] <- NA}
    rs[which(rs[] > 2)] <- 2
    
    cols <- c(colorRampPalette(c("dark green","green","yellow","orange","red"))(length(brks)))
    wld <- list("sp.polygons",wrld_simpl,lwd=0.8,first=F)
    grat <- gridlines(wrld_simpl, easts=seq(-180,180,by=5), norths=seq(-90,90,by=5))
    grli <- list("sp.lines",grat,lwd=0.5,lty=2,first=F)
    
    if (length(cellNo) > 0) {
      layt <- list(pts1,wld,grli)
    } else {
      layt <- list(wld,grli)
    }
    
    tiffName <- paste(out_rs_dir,"/yobs_by_ypred.tif",sep="")
    tiff(tiffName,res=300,compression="lzw",height=ht,width=wt)
    spplot(rs,sp.layout=layt,col.regions=cols,
           par.settings=list(fontsize=list(text=8)),
           at=brks,pretty=brks)
    dev.off()
    
    
    #ratio obs to pred sd yield
    ht <- 1000
    fct <- (sdo_sdp@extent@xmin-sdo_sdp@extent@xmax)/(sdo_sdp@extent@ymin-sdo_sdp@extent@ymax)
    wt <- ht*(fct+.1)
    
    rs <- sdo_sdp
    if (length(cellNo) > 0) {rs[cellNo] <- NA}
    rs[which(rs[] > 2)] <- 2
    
    brks <- seq(0,2,by=.2)
    brks.lab <- round(brks,2)
    cols <- c(colorRampPalette(c("dark green","green","yellow","orange","red"))(length(brks)))
    wld <- list("sp.polygons",wrld_simpl,lwd=0.8,first=F)
    grat <- gridlines(wrld_simpl, easts=seq(-180,180,by=5), norths=seq(-90,90,by=5))
    grli <- list("sp.lines",grat,lwd=0.5,lty=2,first=F)
    
    if (length(cellNo) > 0) {
      layt <- list(pts1,wld,grli)
    } else {
      layt <- list(wld,grli)
    }
    
    tiffName <- paste(out_rs_dir,"/sdobs_by_sdpred.tif",sep="")
    tiff(tiffName,res=300,compression="lzw",height=ht,width=wt)
    spplot(rs,sp.layout=layt,col.regions=cols,
           par.settings=list(fontsize=list(text=8)),
           at=brks,pretty=brks)
    dev.off()
    
    
    #correlation coefficient and those gridcells with positive and strong (p<0.05) plotted on top
    rs <- raster(paste(out_rs_dir,"/ccoef.asc",sep=""))
    if (length(cellNo) > 0) {rs[cellNo] <- NA}
    ht <- 1000
    fct <- (rs@extent@xmin-rs@extent@xmax)/(rs@extent@ymin-rs@extent@ymax)
    wt <- ht*(fct+.1)
    
    brks <- seq(-1,1,length.out=21)
    brks.lab <- round(brks,2)
    cols <- c(colorRampPalette(c("red","orange","yellow","green","dark green"))(length(brks)))
    wld <- list("sp.polygons",wrld_simpl,lwd=0.8,first=F)
    grat <- gridlines(wrld_simpl, easts=seq(-180,180,by=5), norths=seq(-90,90,by=5))
    grli <- list("sp.lines",grat,lwd=0.5,lty=2,first=F)
    
    #plot significant and positive correlations on top
    xysig <- cbind(x=out_all$X[which(out_all$CCOEF > 0 & out_all$PVAL <= 0.05 & cells$AHRATIO >= 0.2)],
                   y=out_all$Y[which(out_all$CCOEF > 0 & out_all$PVAL <= 0.05 & cells$AHRATIO >= 0.2)])
    xysig <- SpatialPoints(xysig)
    pts2 <- list("sp.points", xysig, pch = 20, col = "black", cex=0.75, lwd=0.6,first=F)
    
    if (length(cellNo) > 0) {
      layt <- list(pts2,pts1,wld,grli)
    } else {
      layt <- list(pts2,wld,grli)
    }
    
    tiffName <- paste(out_rs_dir,"/ccoef.tif",sep="")
    tiff(tiffName,res=300,compression="lzw",height=ht,width=wt)
    spplot(rs,sp.layout=layt,col.regions=cols,
           par.settings=list(fontsize=list(text=8)),
           at=brks,pretty=brks)
    dev.off()
    
    
    
    #rmse
    rs <- raster(paste(out_rs_dir,"/rmse.asc",sep=""))
    if (length(cellNo) > 0) {rs[cellNo] <- NA}
    ht <- 1000
    fct <- (rs@extent@xmin-rs@extent@xmax)/(rs@extent@ymin-rs@extent@ymax)
    wt <- ht*(fct+.1)
    
    brks <- seq(min(rs[],na.rm=T),max(rs[],na.rm=T),length.out=25)
    brks.lab <- round(brks,2)
    cols <- c(colorRampPalette(c("dark green","green","yellow","orange","red"))(length(brks)))
    wld <- list("sp.polygons",wrld_simpl,lwd=0.8,first=F)
    grat <- gridlines(wrld_simpl, easts=seq(-180,180,by=5), norths=seq(-90,90,by=5))
    grli <- list("sp.lines",grat,lwd=0.5,lty=2,first=F)
    
    if (length(cellNo) > 0) {
      layt <- list(pts1,wld,grli)
    } else {
      layt <- list(wld,grli)
    }
    
    tiffName <- paste(out_rs_dir,"/rmse.tif",sep="")
    tiff(tiffName,res=300,compression="lzw",height=ht,width=wt)
    spplot(rs,sp.layout=layt,col.regions=cols,
           par.settings=list(fontsize=list(text=8)),
           at=brks,pretty=brks)
    dev.off()
    
    
    #percent rmse
    rs <- raster(paste(out_rs_dir,"/p_rmse.asc",sep=""))
    if (length(cellNo) > 0) {rs[cellNo] <- NA}
    rs[which(rs[] > 100)] <- 101
    ht <- 1000
    fct <- (rs@extent@xmin-rs@extent@xmax)/(rs@extent@ymin-rs@extent@ymax)
    wt <- ht*(fct+.1)
    
    brks <- c(seq(0,100,length.out=25),max(rs[],na.rm=T))
    brks.lab <- c(round(seq(0,100,length.out=25),0),">100")
    cols <- c(colorRampPalette(c("dark green","green","yellow","orange","red"))(length(brks)))
    wld <- list("sp.polygons",wrld_simpl,lwd=0.8,first=F)
    grat <- gridlines(wrld_simpl, easts=seq(-180,180,by=5), norths=seq(-90,90,by=5))
    grli <- list("sp.lines",grat,lwd=0.5,lty=2,first=F)
    
    if (length(cellNo) > 0) {
      layt <- list(pts1,wld,grli)
    } else {
      layt <- list(wld,grli)
    }
    
    tiffName <- paste(out_rs_dir,"/p_rmse.tif",sep="")
    tiff(tiffName,res=300,compression="lzw",height=ht,width=wt)
    spplot(rs,sp.layout=layt,col.regions=cols,
           par.settings=list(fontsize=list(text=8)),
           at=brks,pretty=brks.lab)
    dev.off()
    
    
    #optimal start of sowing window
    rs <- raster(paste(out_rs_dir,"/sow_date.asc",sep=""))
    if (length(cellNo) > 0) {rs[cellNo] <- NA}
    ht <- 1000
    fct <- (rs@extent@xmin-rs@extent@xmax)/(rs@extent@ymin-rs@extent@ymax)
    wt <- ht*(fct+.1)
    
    brks <- seq(min(rs[],na.rm=T),max(rs[],na.rm=T),length.out=25)
    brks.lab <- round(brks,0)
    cols <- c(colorRampPalette(c("dark green","green","yellow","orange","red"))(length(brks)))
    wld <- list("sp.polygons",wrld_simpl,lwd=0.8,first=F)
    grat <- gridlines(wrld_simpl, easts=seq(-180,180,by=5), norths=seq(-90,90,by=5))
    grli <- list("sp.lines",grat,lwd=0.5,lty=2,first=F)
    
    if (length(cellNo) > 0) {
      layt <- list(pts1,wld,grli)
    } else {
      layt <- list(wld,grli)
    }
    
    tiffName <- paste(out_rs_dir,"/sow_date.tif",sep="")
    tiff(tiffName,res=300,compression="lzw",height=ht,width=wt)
    spplot(rs,sp.layout=layt,col.regions=cols,
           par.settings=list(fontsize=list(text=8)),
           at=brks,pretty=brks.lab)
    dev.off()
    
    
    #plot cell numbers
    rs <- raster(msk)
    rs[out_all$CELL] <- 1
    
    tiffName <- paste(out_rs_dir,"/cell_id.tif",sep="")
    tiff(tiffName,res=300,compression="lzw",height=ht,width=wt,pointsize=5)
    par(mar=c(3,3,1,1))
    plot(rs,legend=F)
    text(x=out_all$X,y=out_all$Y,labels=out_all$CELL,cex=0.55)
    plot(wrld_simpl,add=T,lwd=0.25)
    grid()
    dev.off()
    
    
    ##scatter gram of spatial consistency
    out_all$AHRATIO <- cells$AHRATIO
    out_sct <- out_all[which(out_all$AHRATIO >= 0.2),]
    
    rval <- cor.test(out_all$Y_PRED,out_all$Y_OBS)$estimate
    pval <- cor.test(out_all$Y_PRED,out_all$Y_OBS)$p.value
    
    lims <- c(0,max(out_sct$Y_PRED,out_sct$Y_OBS))
    
    tiffName <- paste(out_rs_dir,"/yobs_ypred_xy.tif",sep="")
    tiff(tiffName,res=300,compression="lzw",height=ht,width=wt,pointsize=5)
    par(mar=c(5,5,2,1))
    plot(out_sct$Y_PRED,out_sct$Y_OBS,pch=20,cex=0.75,xlim=lims,ylim=lims,
         xlab="Predicted yield (kg/ha)",
         ylab="Observed yield (kg/ha)",
         main=paste("CCOEF=",round(rval,3),"(p=",round(pval,6),")",sep=""))
    abline(0,1)
    grid()
    dev.off()
    
    
    lims <- c(0,max(out_sct$YSD_PRED,out_sct$YSD_OBS))
    
    rval <- cor.test(out_all$YSD_PRED,out_all$YSD_OBS)$estimate
    pval <- cor.test(out_all$YSD_PRED,out_all$YSD_OBS)$p.value
    
    tiffName <- paste(out_rs_dir,"/sdobs_sdpred_xy.tif",sep="")
    tiff(tiffName,res=300,compression="lzw",height=ht,width=wt,pointsize=5)
    par(mar=c(5,5,2,1))
    plot(out_sct$YSD_PRED,out_sct$YSD_OBS,pch=20,cex=0.75,xlim=lims,ylim=lims,
         xlab="Predicted yield s.d. (kg/ha)",
         ylab="Observed yield s.d. (kg/ha)",
         main=paste("CCOEF=",round(rval,3),"(p=",round(pval,6),")",sep=""))
    abline(0,1)
    grid()
    dev.off()
  }
  
}
