#' Plots from a StepReg object
#'
#' plot.StepReg visualizes the variable selection procedure using a StepReg object
#'
#' @param x StepReg object
#' 
#' @param strategy Select which strategy to be displayed, default is the first name of StepReg object.
#' 
#' @param process Select which process of stepwise regression to be displayed from 'details' and 'overview', default is 'overview'.
#' 
#' @param num_digits The number of digits to keep when rounding the results. 
#' Default is 6.
#' 
#' @param ... Not used
#'
#' @return A list of plots comprising the selection detail plot and selection 
#' summary plot for each strategy.
#' 
#' @import ggplot2
#' 
#' @importFrom stringr str_split
#' 
#' @importFrom dplyr group_by filter
#' 
#' @importFrom ggrepel geom_label_repel
#' 
#' @export
#'
#' @examples
#' \dontrun{
#' data(mtcars)
#' formula <- mpg ~ .
#' x <- stepwise(formula = formula,
#'               data = mtcars,
#'               type = "linear",
#'               strategy = c("forward","bidirection","subset"),
#'               metric = c("AIC","BIC","SL"))
#' plot(x)
#' plot(x, strategy = "forward", process = "overview")
#' }

plot.StepReg <- function(x, strategy = attr(x,"nonhidden"), process = c("overview", "details"), num_digits = 6, ...) {
  process <- match.arg(process)
  strategy <- match.arg(strategy)
  
  details_list <- x$details
  arguments <- x$arguments
  test_method <- arguments[arguments$Parameter %in% "test method",2]
  overview_list <- x$overview
  strategy_vec <- unlist(str_split(arguments[arguments$Parameter %in% "selection strategy",2]," & "))
  
  if(!strategy %in% strategy_vec){
    stop(paste0(strategy," is not found in StepReg object"))
  }
  
  overview_process_table <- overview_list[[strategy]]
  if (strategy == "subset") {
    overview_df <- lapply(overview_process_table, function(df) {
      df <- cbind(df,colnames(df)[2])
      colnames(df) <- c("Step", "MetricValue", "Variable", "Metric")
      return(df)
    })
  } else {
    overview_df <- lapply(overview_process_table, function(df) {
      df <- cbind(df,colnames(df)[ncol(df)])
      var_sym <- rep(NA, nrow(df))
      var_plus <- paste0("(+)", df[, colnames(df) %in% "EffectEntered"])
      index_plus <- which(!var_plus %in% "(+)")
      var_minus <- paste0("(-)", df[, colnames(df) %in% "EffectRemoved"])
      index_minus <- which(!var_minus %in% "(-)")
      var_sym[index_plus] <- var_plus[index_plus]
      var_sym[index_minus] <- var_minus[index_minus]
      df <- cbind(df[,c(1,ncol(df)-1,ncol(df))],var_sym)
      colnames(df) <- c("Step", "MetricValue", "Metric", "Variable")
      return(df)
    })
  }
  names(overview_df) <- NULL
  plot_overview <- do.call(rbind, overview_df)
  plot_overview$Step <- as.numeric(plot_overview$Step)
  plot_overview$MetricValue <- as.numeric(plot_overview$MetricValue)
  
  if(strategy %in% names(details_list)) {
    details_process_table <- details_list[[strategy]]
    plot_details <- do.call(rbind, details_process_table)
  }
  
  if(process == "details"){
    if(strategy != "subset") {
      p1 <- plotStepwiseDetail(plot_details, num_digits)
    } else {
      #From SAS description: For two models A and B, each having the same number of explanatory variables, model A is considered to be better than model B if the global score chi-square statistic for A exceeds that for B.
      plot_overview <- plot_overview %>%
        group_by(.data$Step, .data$Metric) %>%
        filter(ifelse(.data$Metric == "SL", .data$MetricValue == max(.data$MetricValue), .data$MetricValue == min(.data$MetricValue)))
      p1 <- plotSubsetDetail(plot_overview)
    }
    return(p1)
  } else {
    ## make a dual y-axis with log10 transformed for 'SL' if 'SL' is selected
    if(strategy != 'subset') {
      if("SL" %in% plot_overview$Metric) {
        plot_overview[plot_overview$Metric == "SL",]$MetricValue <- plot_details[plot_details$metric == "SL" & plot_details$Selection %in% c("Entry","Remove"),"value"]
        plot_overview$MetricValue[plot_overview$MetricValue %in% Inf] <- max(plot_overview$MetricValue[!plot_overview$MetricValue %in% Inf]) * 1.1
        a <- range(log10(plot_overview[plot_overview$Metric == "SL", ]$MetricValue))
        b <- range(plot_overview[plot_overview$Metric != "SL", ]$MetricValue)
        
        p2 <- plotStepwiseSummaryDualY(x, plot_overview, a, b, strategy)
      } else {
        p2 <- plotStepwiseSummarySingleY(plot_overview)
      }
    } else {
      p2 <- plotSubsetSummary(plot_overview, test_method)
    }
    p2 <- p2 +
      scale_x_continuous(breaks = plot_overview$Step) + 
      labs(title =paste0("Selection overview: ",strategy)) + 
      theme_light()
    return(p2)
  }
}

plotStepwiseSummaryDualY <- function(x, df, a, b, n){
  if(all(df$Metric %in% "SL")) {
    p2 <- ggplot(df, aes(x = .data$Step, group = .data$Metric)) +
      geom_point(aes(y = (log10(.data$MetricValue) - a[1])/diff(a), color = .data$Metric)) + 
      geom_label_repel(aes(y = (log10(.data$MetricValue) - a[1])/diff(a), color = .data$Metric, label = .data$Variable),
                       label.size = 0.05,
                       show.legend = FALSE) + 
      scale_y_continuous(
        labels = function(x) sprintf("%.1e", 10^(x * diff(a) + a[1])),
        breaks = (pretty(log10(df$MetricValue)) - a[1])/diff(a), 
        name = "SL (p value)") + 
      geom_line(aes(y = (log10(.data$MetricValue) - a[1])/diff(a), color = .data$Metric))
  } else {
    p2 <- ggplot(df, aes(x = .data$Step, group = .data$Metric)) +
      geom_point(aes(y = ifelse(.data$Metric == "SL", (log10(.data$MetricValue) - a[1])/diff(a), (.data$MetricValue - b[1])/diff(b)), color = .data$Metric)) + 
      geom_label_repel(aes(y = ifelse(.data$Metric == "SL", (log10(.data$MetricValue) - a[1])/diff(a), (.data$MetricValue - b[1])/diff(b)), color = .data$Metric, label = .data$Variable),
                       label.size = 0.05,
                       show.legend = FALSE) + 
      scale_y_continuous(
        labels = function(x) sprintf("%.1e", 10^(x * diff(a) + a[1])),
        breaks = (pretty(log10(df$MetricValue)) - a[1])/diff(a), 
        name = "SL (p value)",
        sec.axis = sec_axis(~(diff(b) * . + b[1]), name = paste0(unique(df$Metric)[!unique(df$Metric) == "SL"],collapse=" / "))) + 
      geom_line(aes(y = ifelse(.data$Metric == "SL", (log10(.data$MetricValue) - a[1])/diff(a), (.data$MetricValue - b[1])/diff(b)), color = .data$Metric))
  }
  if(n == "forward") {
    sle <- x[[1]][which(x[[1]][,1] %in% "significance level for entry (sle)"), 2]
    p2 <- p2 + 
      geom_hline(yintercept=(log10(as.numeric(sle)) - a[1])/diff(a), linetype="dashed", color = "gray") + 
      geom_text(aes(1.5,(log10(as.numeric(sle)) - a[1])/diff(a), label = paste0("sle=",sle), vjust = -1), color = "gray")
  } else if (n == "backward") {
    sls <- x[[1]][which(x[[1]][,1] %in% "significance level for stay (sls)"), 2]
    p2 <- p2 + 
      geom_hline(yintercept=(log10(as.numeric(sls)) - a[1])/diff(a), linetype="dotdash", color = "gray") + 
      geom_text(aes(max(as.numeric(.data$Step)) - 0.5, (log10(as.numeric(sls)) - a[1])/diff(a), label = paste0("sls=",sls), vjust = -1), color = "gray")
  } else {
    sle <- x[[1]][which(x[[1]][,1] %in% "significance level for entry (sle)"), 2]
    sls <- x[[1]][which(x[[1]][,1] %in% "significance level for stay (sls)"), 2]
    p2 <- p2 +
      geom_hline(yintercept=(log10(as.numeric(sle)) - a[1])/diff(a), linetype="dashed", color = "gray") + 
      geom_text(aes(1.5,(log10(as.numeric(sle)) - a[1])/diff(a), label = paste0("sle=",sle), vjust = -1), color = "gray") + 
      geom_hline(yintercept=(log10(as.numeric(sls)) - a[1])/diff(a), linetype="dotdash", color = "gray") + 
      geom_text(aes(max(as.numeric(.data$Step)) - 0.5, (log10(as.numeric(sls)) - a[1])/diff(a), label = paste0("sls=",sls), vjust = -1), color = "gray")
  }
  p2 <- p2 + xlab("Step")
  return(p2)
}

plotStepwiseSummarySingleY <- function(df){
  metricValue <- unique(df$Metric)
  if("SL" %in% metricValue){
    metricValue[which(metricValue %in% "SL")] <- "SL (p value)"
  }
  p2 <- ggplot(data = df) + 
    aes(x = .data$Step,
        y = .data$MetricValue, 
        label = .data$Variable,
        group = .data$Metric) + 
    geom_point(aes(color = .data$Metric)) + 
    geom_line(aes(linetype = .data$Metric, color = .data$Metric)) +
    geom_label_repel(label.size = 0.05,
                     aes(color = .data$Metric),
                     show.legend = FALSE) + 
    xlab("Step") +
    ylab(paste0(metricValue,collapse=" / "))
}

plotSubsetSummary <- function(df, test_method) {
  metricValue <- unique(df$Metric)
  if("SL" %in% metricValue){
    metricValue[metricValue %in% "SL"] <- paste0("SL (",test_method," statistics)")
  }
  p2 <- ggplot(data = df) + 
    aes(x = .data$Step,
        y = .data$MetricValue, 
        label = .data$Variable,
        group = .data$Metric) + 
    geom_point(aes(color = .data$Metric)) + 
    geom_line(aes(linetype = .data$Metric, color = .data$Metric)) +
    xlab("Variable number") +
    ylab(paste0(metricValue,collapse=" / "))
  return(p2)
}

plotStepwiseDetail <- function(df, num_digits) {
  p1 <- ggplot(df, 
               aes(x = .data$step,
                   y = .data$variable)) +
    geom_tile(aes(fill = .data$Selection), width = 0.99, height = 0.95, color = "black") +
    geom_text(aes(label = round(.data$value, num_digits)),
              color = "black",
              size = 2) +
    scale_fill_manual(values = c("Entry" = "palegreen2", "Remove" = "tan3","No" = "gray80")) +
    theme_light() + 
    scale_x_continuous(breaks = unique(df$step)) + 
    theme(axis.text.y = element_text(size = 8),
          strip.text = element_text(color = "black")) +  # Adjust text color in facet labels
    facet_wrap(~ .data$metric, ncol=1) + 
    theme(strip.background = element_rect(colour = "black", fill = "gray80")) +
    ggtitle(paste0("Selection details: ", df$strategy[1])) + 
    ylab("Predictors") + 
    xlab("Step")
  return(p1)
}

plotSubsetDetail <- function(plot_overview) {
  #-------------------------
  #subset works for SL in logit(need to test)
  variable_list <- lapply(strsplit(plot_overview$Variable, " "), function(x) x[x != ""])
  tile_df <- expand.grid(Variable = variable_list[[length(variable_list)]], Step = plot_overview$Step)
  tile_df$Metric <- rep(plot_overview$Metric, each = length(variable_list[[length(variable_list)]]))
  tile_df$Selection <- mapply(function(metric, step, variable) {
    df2_1 <- plot_overview[plot_overview$Metric == metric, ]
    df2_2 <- df2_1[df2_1$Step == step, ]
    any(variable %in% strsplit(df2_2$Variable, " ")[[1]])
  }, tile_df$Metric, tile_df$Step, tile_df$Variable)
  tile_df$Selection <- ifelse(tile_df$Selection, "Entry", "No")
  
  p1 <- ggplot(tile_df, aes(x = .data$Step, y = .data$Variable, fill = .data$Selection)) +
    geom_tile(width = 0.99, height = 0.95, color = "black") +
    scale_fill_manual(values = c("Entry" = "palegreen2", "No" = "gray80")) +
    labs(x = "Step", y = "Predictors", title = "Selection details: subset") +
    scale_x_continuous(breaks = plot_overview$Step) + 
    xlab("Variable number") +
    facet_wrap(~ .data$Metric, ncol=1) + 
    theme(strip.background = element_rect(colour = "black", fill = "gray80"))
}


