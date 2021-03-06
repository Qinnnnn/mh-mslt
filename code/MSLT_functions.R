# ---- Packages for functions ----

library(dplyr)
library(tidyverse)
library(compiler)   # for byte code compilation

# Method reference: 1.	Barendregt JJ, Oortmarssen vGJ, Murray CJ, Vos T. A generic model for the assessment of disease epidemiology: the computational basis of DisMod II. Popul Health Metr. 2003;1(1):4-.
# Naming convention for functions: Function.Name


# --- IsNanDataFrame ---
## For interpolation generation, input data frame for interpolation has nan values that we replace with 0. 

IsNanDataFrame <- function(x)
  do.call(cbind, lapply(x, is.nan))

# --- IsInfDataFrame ---
## For interpolation generation, input data frame for interpolation has inf values that we replace with 0. 
IsInfDataFrame <- function(x)
  do.call(cbind, lapply(x, is.infinite))

# ---- RunLifeTable ----

## Function to generate age and sex life table for baseline and scenario.

RunLifeTable <- function(in_idata, in_sex, in_mid_age)
{
  
  # Create a life table starting data frame from input data. 
  
  lf_df <- in_idata[in_idata$age >= in_mid_age & in_idata$sex == in_sex,] 
  lf_df <- lf_df[,colnames(lf_df) %in% c('sex', 'age', 'pyld_rate', 'mx')]
  
  # Create list life table variables. First as vector and then added to the data frame at the end.
  ## We model up to 100, that is the reason for the age limit in the function
  
  # probability of dying

  qx <-  ifelse(lf_df$age < 100, 1 - exp(-1 * lf_df$mx), 1)
  
  # number of survivors year 1 simulation
  
  num_row <- nrow(lf_df)
  lx <- rep(0,num_row)
  lx[1] <- as.numeric(in_idata$population_number[in_idata$age == in_mid_age & in_idata$sex == in_sex]) 
  
  # number died in year 1 simulation
  
  dx <- rep(0,num_row)
  dx[1] <- lx[1] * qx[1]
  
  # number of survivors and who die from year 2 onwards. 
  
  for (i in 2:num_row){
    lx[i] <- lx[i - 1] - dx[i - 1]
    dx[i] <- lx[i] * qx[i]
  }
  
  # number of persons lived by cohort to age x + 1/2 (average people)
 
  Lx <- rep(0,num_row)
  
  # for years up to 99
  
  for (i in 1:(num_row-1))
    Lx[i] <- (lx[i] + lx[i + 1]) / 2
  
  # for year 100, cohort dies at 100 if anyone left
  
  Lx[num_row] <- lx[num_row] / lf_df$mx[num_row]
  
  
  # create life expectancy variable
  ex <- rep(0,num_row)
  for (i in 1:num_row){
    ex[i] <- sum(Lx[i:num_row]) / lx[i]
  }
  
  # create health adjusted life years variable 
  
  Lwx <- Lx * (1 - lf_df$pyld_rate)
  
  # create health adjusted life expectancy variable
  ewx <- rep(0,num_row)
  for (i in 1:num_row){
    ewx[i] <- sum(Lwx[i:num_row]) / lx[i]
  }
  
  lf_df$qx <- qx
  lf_df$lx <- lx
  lf_df$dx <- dx
  lf_df$Lx <- Lx
  lf_df$ex <- ex
  lf_df$Lwx <- Lwx
  lf_df$ewx <- ewx
  lf_df
}

# ---- RunDisease ----

## Function to generate age and sex disease life table for baseline and scenario.
## Remission is not modelled.

RunDisease <- function(in_idata, in_mid_age, in_sex, in_disease) 
  
{
  
  
  # create disease variable for the disease life table function 
  dw_disease <- paste("dw_adj", in_disease, sep = "_")
  incidence_disease <- paste("incidence", in_disease, sep = "_")
  case_fatality_disease <- paste("case_fatality", in_disease, sep = "_")
  
  ## add generic variable names to the source data frame (in_idata)
  in_idata$dw_disease <- in_idata[[dw_disease]]
  in_idata$incidence_disease <- in_idata[[incidence_disease]]
  in_idata$case_fatality_disease <- in_idata[[case_fatality_disease]]
  
  # Select columns for lifetable calculations
  
  ##BZ: back yo using filtering, otherwise the life tables are not run by cohort (age and sex)
  dlt_df <- dplyr::filter(in_idata, age >= in_mid_age & sex == in_sex) %>% 
    dplyr::select(sex, age, dw_disease, incidence_disease, case_fatality_disease)
  
  ##BZ: Rob, line 264 does not filter by age and sex, each disease life table starts at firt age cohort (e.g. 17) and by gender. 
  
  # dlt_df <- in_idata[,colnames(in_idata) %in% c('sex', 'age', 'dw_disease', 'incidence_disease', 'case_fatality_disease')] # dplyr::select(sex, age, dw_disease, incidence_disease, case_fatality_disease)
  
  dlt_df$disease <- in_disease
  
  # create list of life table variables. Created as vectors and then added to dataframe. 
  # See see methods in: 1) Concept and original calculations: Barendregt, J. J., et al. (1998). "Coping with multiple morbidity in a life table." Math Popul Stud 7(1): 29-49. 
  # and 2) Latest version, variables below calculated from it: Barendregt, J. J., et al. (2003). "A generic model for the assessment of disease epidemiology: the computational basis of DisMod II." Popul Health Metr 1(1): 4-4.
  
  
  ### lx, qx, wx and vx are intermediate variables, 
  
  lx <- dlt_df$incidence_disease + dlt_df$case_fatality_disease
  qx <-  sqrt((dlt_df$incidence_disease - dlt_df$case_fatality_disease) * (dlt_df$incidence_disease - dlt_df$case_fatality_disease))
  wx <- exp(-1*(lx+qx)/2)
  vx <- exp(-1*(lx-qx)/2)
  
  ## Healthy (Sx), Disease (Cx) and Death (Dx), total (Tx) (control check, has to be 1000), total alive (Ax)
  ## persons years live at risk (PYx), prevalence rate (px), mortality rate (mx)
  ## Remission and mortality from other causes were replaced by zero in the formulas (as we assume no remission and independence of disease mortality with total mortlaity). 
  
  ### First create empty variables
  
  number_of_ages <- nrow(dlt_df)
  Sx <- Cx <- Dx <- Tx  <- Ax <- PYx <- px <- mx <- rep(0,number_of_ages)
  cfds <- dlt_df$case_fatality_disease
  ages <- dlt_df$age
  
  #### Starts with 1000 healthy (Sx) and total (Ax) people. 
  
  Sx[1] <- Ax[1] <- 1000
  
  ##### start with variables without calculation exceptions
  
  ##### variables without exceptions (else includes exception for year one of the simulation)  
  for (i in 2:(number_of_ages-1)){ ##!! this can go to "number_of_ages" now (?)
    if(qx[i-1] > 0){
      
      ### The following five variables are created to simplify Sx, Cx and Dx calculations, and do not form part of the disease life tables.
      vxmwx <- vx[i-1] - wx[i-1]
      SxpCx <- Sx[i-1]+Cx[i-1]
      dqx <- 2 * qx[i-1]
      qxmlx <- qx[i-1] - lx[i-1]
      qxplx <- qx[i-1] + lx[i-1]
      
      ### Healthy (Sx), Diseases (Cx) and Death from the Disease (Dx)
      
      Sx[i] <- Sx[i-1] * (2*vxmwx * cfds[i-1]  + (vx[i-1] * qxmlx + wx[i-1] * qxplx)) / dqx
      Cx[i] <- -1*(vxmwx*(2*(cfds[i-1]  * SxpCx - lx[i-1] * Sx[i-1]) - Cx[i-1] * lx[i-1]) - Cx[i-1] * qx[i-1] * (vx[i-1]+wx[i-1])) / dqx
      Dx[i] <- (vxmwx * (2 * cfds[i-1] * Cx[i-1] - lx[i-1]*SxpCx)- qx[i-1] * SxpCx*(vx[i-1]+wx[i-1]) + dqx * (SxpCx+Dx[i-1]) ) / dqx
    }else{
      Sx[i] <- Sx[i - 1] 
      Cx[i] <- Cx[i - 1]
      Dx[i] <- Dx[i - 1]
    }
  }
  

  Tx   <- Sx + Cx + Dx 
  Ax <- Sx + Cx
  
  first_indices <- 1:(number_of_ages-1)
  last_indices <- 2:number_of_ages
  PYx <- (Ax[first_indices] + Ax[last_indices])/2
  mx[first_indices] <- (Dx[last_indices] - Dx[first_indices])/PYx[first_indices]
  mx[mx<0] <- 0
  px[first_indices] <- (Cx[last_indices] + Cx[first_indices])/2/PYx[first_indices]
  
  dlt_df$Tx <- Tx
  dlt_df$mx <- mx
  dlt_df$px <- px
  dlt_df
}



# RunNonDisease

RunNonDisease <- function(in_idata, in_sex, in_mid_age, in_non_disease)
  
{
  df <- in_idata[,colnames(in_idata) %in% c('sex', 'age',  paste0("deaths_rate_", in_non_disease), paste0("ylds_rate_", in_non_disease))]
  
  ## Delete names disease from columns to simplify calculations
  
  names(df)[names(df) == paste0("deaths_rate_", in_non_disease)] <-
    paste("deaths_rate_bl")
  
  names(df)[names(df) == paste0("ylds_rate_", in_non_disease)] <-
    paste("ylds_rate_bl")
  
  
  return(df)
}


# ---- GenAggregate ----

# Function to aggreate outcomes by age an sex


GenAggregate <- function(in_data, in_cohorts, in_population, in_outcomes){
  
  
  # in_data <- output_df
  # in_population <- "males"
  # in_cohorts <- 10
  # in_outcomes <- c('inc_num_bl_ihd', 'inc_num_sc_ihd')
  
  age_cohort_list <- list()
  td <- in_data
  aggr <- list()
  l_age <-  min(td$age_cohort)
  for (i in 1:in_cohorts){
    if (l_age <= 100){
      ld <- dplyr::filter(td, age_cohort == l_age)
      
      if (in_population != "total")
        ld <- dplyr::filter(ld, sex == in_population)
      if (length(in_outcomes) > 0)
        ld <- dplyr::select(ld, age, sex, in_outcomes)
      if (i == 1){
        aggr <- append(aggr, as.list(ld))
        aggr <- as.data.frame(aggr)
        names(aggr) <- paste(names(aggr), l_age, in_population, sep = "_" )
      }
      else {
        n_rows <-  nrow(aggr) - nrow(ld)
        ld[(nrow(ld) + 1):(nrow(ld) + n_rows),] <- NA
        names(ld) <- paste(names(ld), l_age, in_population, sep = "_" )
        aggr <- cbind(aggr, ld)
      }
      
      l_age <- l_age + 5
    }
  }
  
  for (i in 1:length(in_outcomes)){
    aggr[[paste0("total_",in_outcomes[i])]] <- dplyr::select(aggr, starts_with(in_outcomes[i])) %>% rowSums(na.rm = T)
    
  }
  
  aggr
}

# ---- PlotOutput ----

# Function to generate graphs by age and sex, per outcome of interest.


PlotOutput <- function(in_data, in_age, in_population, in_outcomes, in_legend = "", in_disease = ""){
  
  #   # in_data <- output_df
  #   # in_population <- "male"
  #   # in_age <- 22
  #   # in_outcomes <- c('age', 'inc_num_bl_ihd', 'inc_num_sc_ihd')
  #   # in_legend <- "none"
  #   # in_cols <- c('alpha', 'beta')
  #
  data <- in_data
  #
  if (in_population != "total")
    data <- dplyr::filter(data, sex == in_population)
  if (length(in_age) > 0)
    data <- dplyr::filter(data, age_cohort == in_age)
  if (length(in_outcomes) > 0)
    data <- dplyr::select(data, in_outcomes)
  
  td <- data
  p <- ggplot(data = td, aes (x = td[[in_outcomes[[1]]]]))
  
  # loop
  for (i in 2:length(in_outcomes)) {
    # use aes_string with names of the data.frame
    p <- p + geom_line(aes_string(y = td[[in_outcomes[i]]], color = as.factor(in_outcomes[i])), size = 0.8) +
      
      theme_classic()
    
    
  }
  
  p <- p + scale_color_discrete(name = paste(in_legend), labels = c("Baseline", "Difference", "Scenario")) +
    theme(legend.title = element_text(size = 9))
  
  p <- p + xlab ('Simulation year') + ylab ('Cases') + labs (title = ifelse(length(in_disease) > 0, paste(in_age, in_population, in_disease, sep = " "), "")) +
    
    
    #
    #                                                                 # in_disease, paste('Cohort', in_age, "years old", in_population, sep = " "))) +
    theme(plot.title = element_text(hjust = 0.5, size = 9)) +
    theme(legend.text = element_text(size = 9)) +
    # theme(axis.title.x = element_text(size = 7)) +
    xlim(in_age, 100) +
    geom_hline(yintercept=0, linetype="dashed", color = "black")
  #
  #
  return(p)
  #
  last_plot()
  #
  #
}

PlotOutput_compiled <- cmpfun(PlotOutput)
ggsave_compiled <- cmpfun(ggsave)

system.time(PlotOutput_compiled())
system.time(PlotOutput())

# ---- GridArrangSharedLegend ----
# Function to general combined labels for multiple plots in a page

GridArrangSharedLegend <- function(..., ncol = length(list(...)), nrow = 1, position = c("bottom", "right"), mainTitle = "", mainLeft = "", mainBottom = "") {
  
  plots <- list(...)
  position <- match.arg(position)
  g <- ggplotGrob(plots[[1]] + theme(legend.position = position))$grobs
  legend <- g[[which(sapply(g, function(x) x$name) == "guide-box")]]
  lheight <- sum(legend$height)
  lwidth <- sum(legend$width)
  gl <- lapply(plots, function(x) x + theme(legend.position="none"))
  gl <- c(gl, ncol = ncol, nrow = nrow, top = mainTitle, left = mainLeft, bottom = mainBottom)
  
  combined <- switch(position,
                     "bottom" = arrangeGrob(do.call(arrangeGrob, gl),
                                            legend,
                                            ncol = 1,
                                            heights = unit.c(unit(1, "npc") - lheight, lheight)),
                     "right" = arrangeGrob(do.call(arrangeGrob, gl),
                                           legend,
                                           ncol = 2,
                                           widths = unit.c(unit(1, "npc") - lwidth, lwidth)))
  
  
  #grid.newpage()
  grid.draw(combined)
  
  # return gtable invisibly
  invisible(combined)
  
}


g_legend <- function(a.gplot){
  tmp <- ggplot_gtable(ggplot_build(a.gplot))
  leg <- which(sapply(tmp$grobs, function(x) x$name) == "guide-box")
  legend <- tmp$grobs[[leg]]
  return(legend)
}


# ---- PlotGBD (may need to update) ----
# Function to generate GBD graphs to compare data national to local (USED in GBD COMPARE############################

PlotGBD <- function(in_data1, in_data2, in_sex, in_cause, in_measure) {
  
  # in_data1 <- GBDEngland
  # in_data2 <- GBDGL
  # in_sex <- "male"
  # in_cause <- "all causes"
  # in_measure <- "deaths"
  
  
  data1 <- dplyr::filter(in_data1, sex == in_sex, cause == in_cause & measure == in_measure) %>% dplyr::select(measure, location, sex, age, metric, cause, one_rate, age_cat)     
  
  data2 <- dplyr::filter(in_data2, sex == in_sex, cause == in_cause & measure == in_measure) %>% dplyr::select(measure, location, sex, age, metric, cause, one_rate, age_cat)     
  
  
  p <- ggplot(data = data1, aes(age_cat,one_rate)) +
    geom_line(aes(color = "England"))+
    geom_line(data = data2, aes(color = "Greater London"))+
    labs(colour="Locations",x="Age",y= paste(in_cause, in_measure, sep = " "))+
    labs (title = paste("Compare", in_cause, in_measure, in_sex, sep = " "), size=14) + 
    theme_classic()
  print(p)
}

