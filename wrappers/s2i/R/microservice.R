library(plumber)
library(jsonlite)
library(optparse)
library(methods)
library(urltools)
library(stringi)

parseQS <- function(qs){
  if (is.null(qs) || length(qs) == 0 || qs == "") {
    return(list())
  }
  if (stri_startswith_fixed(qs, "?")) {
    qs <- substr(qs, 2, nchar(qs))
  }
  
  parts <- strsplit(qs, "&", fixed = TRUE)[[1]]
  kv <- strsplit(parts, "=", fixed = TRUE)
  kv <- kv[sapply(kv, length) == 2] # Ignore incompletes
  
  keys <- sapply(kv, "[[", 1)
  keys <- unname(sapply(keys, url_decode))
  
  vals <- sapply(kv, "[[", 2)
  vals[is.na(vals)] <- ""
  vals <- unname(sapply(vals, url_decode))
  
  ret <- as.list(vals)
  names(ret) <- keys
  
  # If duplicates, combine
  combine_elements <- function(name){
    unname(unlist(ret[names(ret)==name]))
  }
  
  unique_names <- unique(names(ret))
  
  ret <- lapply(unique_names, combine_elements)
  names(ret) <- unique_names
  
  ret
}


v <- function(...) cat(sprintf(...), sep='', file=stdout())

validate_json <- function(jdf) {
  if (!"data" %in% names(jdf)) {
    return("data field is missing")
  }
  else if (!("ndarray" %in% names(jdf$data) || "tensor" %in% names(jdf$data)) ) {
    return("data field must contain ndarray or tensor field")
  }
  else{
    return("OK")
  }
}

validate_feedback <- function(jdf) {
  if (!"request" %in% names(jdf))
  {
    return("request field is missing")
  }
  else if (!"reward" %in% names(jdf))
  {
    return("reward field is missing")
  }
  else if (!"data" %in% names(jdf$request)) {
    return("data request field is missing")
  }
  else if (!("ndarray" %in% names(jdf$request$data) || "tensor" %in% names(jdf$request$data)) ) {
    return("data field must contain ndarray or tensor field")
  }
  else{
    return("OK")
  }
}

extract_data <- function(jdf) {
  if ("ndarray" %in% names(jdf$data)){
    jdf$data$ndarray
  } else {
    data <- jdf$data$tensor$values
    dim(data) <- jdf$data$tensor$shape
    data
  }
}

extract_names <- function(jdf) {
  if ("names" %in% names(jdf$data)) {
    jdf$data$names
  } else {
    list()
  }
}

create_response <- function(req_df,res_df){
  if ("ndarray" %in% names(req_df$data)){
    templ <- '{"data":{"names":%s,"ndarray":%s}}'
    names <- toJSON(colnames(res_df))
    values <- toJSON(as.matrix(res_df))
    sprintf(templ,names,values)
  } else {
    templ <- '{"data":{"names":%s,"tensor":{"shape":%s,"values":%s}}}'
    names <- toJSON(colnames(res_df))
    values <- toJSON(c(res_df))
    dims <- toJSON(dim(res_df))
    sprintf(templ,names,dims,values)
  }
}

create_dataframe <- function(jdf) {
  data = extract_data(jdf)
  names = extract_names(jdf)
  df <- data.frame(data)
  colnames(df) <- names
  df
}

# See https://github.com/trestletech/plumber/issues/105
parse_data <- function(req){
  parsed <- parseQS(req$postBody)
  if (is.null(parsed$json))
  {
    parsed <- parseQS(req$QUERY_STRING)
  }
  parsed$json
}

predict_endpoint <- function(req,res,json=NULL,isDefault=NULL) {
  #for ( obj in ls(req) ) { 
  #  print(c(obj,get(obj,envir = req))) 
  #}
  json <- parse_data(req) # Hack as Plumber using URLDecode which doesn't decode +
  jdf <- fromJSON(json)
  valid_input <- validate_json(jdf)
  if (valid_input[1] == "OK") {
    df <- create_dataframe(jdf)
    scores <- predict(user_model,newdata=df)
    res_json = create_response(jdf,scores)
    res$body <- res_json
    res
  } else {
    res$status <- 400 # Bad request
    list(error=jsonlite::unbox(valid_input))
  }
}

send_feedback_endpoint <- function(req,res,json=NULL,isDefault=NULL) {
  json <- parse_data(req)
  jdf <- fromJSON(json)
  valid_input <- validate_feedback(jdf)
  if (valid_input[1] == "OK") {
    request <- create_dataframe(jdf$request)
    if ("truth" %in% names(jdf)){
      truth <- create_dataframe(jdf$truth)
    } else {
      truth <- NULL
    }
    #reward <- jdf$reward
    send_feedback(user_model,request=request,reward=1,truth=truth)
    res$body <- "{}"
    res
  } else {
    res$status <- 400 # Bad request
    list(error=jsonlite::unbox(valid_input))
  }
}


transform_input_endpoint <- function(req,res,json=NULL,isDefault=NULL) {
  json <- parse_data(req)
  jdf <- fromJSON(json)
  valid_input <- validate_json(jdf)
  if (valid_input[1] == "OK") {
    df <- create_dataframe(jdf)
    trans <- transform_input(user_model,newdata=df)
    res_json = create_response(jdf,trans)
    res$body <- res_json
    res
  } else {
    res$status <- 400 # Bad request
    list(error=jsonlite::unbox(valid_input))
  }
}

transform_output_endpoint <- function(req,res,json=NULL,isDefault=NULL) {
  json <- parse_data(req)
  jdf <- fromJSON(json)
  valid_input <- validate_json(jdf)
  if (valid_input[1] == "OK") {
    df <- create_dataframe(jdf)
    trans <- transform_output(user_model,newdata=df)
    res_json = create_response(jdf,trans)
    res$body <- res_json
    res
  } else {
    res$status <- 400 # Bad request
    list(error=jsonlite::unbox(valid_input))
  }
}

route_endpoint <- function(req,res,json=NULL,isDefault=NULL) {
  json <- parse_data(req)
  jdf <- fromJSON(json)
  valid_input <- validate_json(jdf)
  if (valid_input[1] == "OK") {
    df <- create_dataframe(jdf)
    routing <- route(user_model,data=df)
    res_json = create_response(jdf,data.frame(list(routing)))
    res$body <- res_json
    res
  } else {
    res$status <- 400 # Bad request
    list(error=jsonlite::unbox(valid_input))
  }
}

parse_commandline <- function() {
  parser <- OptionParser()
  parser <- add_option(parser, c("-p", "--parameters"), type="character",
                       help="Parameters for component", metavar = "parameters")
  parser <- add_option(parser, c("-m", "--model"), type="character",
                       help="Model file", metavar = "model")
  parser <- add_option(parser, c("-s", "--service"), type="character",
                       help="Service type", metavar = "service", default = "MODEL")
  parser <- add_option(parser, c("-a", "--api"), type="character",
                       help="API type - REST", metavar = "api", default = "REST")
  parser <- add_option(parser, c("-e", "--persistence"), type="integer",
                       help="Persistence", metavar = "persistence", default = 0)
  args <- parse_args(parser, args = commandArgs(trailingOnly = TRUE),
                     convert_hyphens_to_underscores = TRUE)
  
  if (is.null(args$parameters)){
    args$parameters <- Sys.getenv("PREDICTIVE_UNIT_PARAMETERS")
  }
  
  if (args$parameters == ''){
    args$parameters = "[]"
  }
  
  args
}


extract_parmeters <- function(params) {
  j = fromJSON(params)
  values <- list()
  names <- list()
  for (i in seq_along(j))
  {
    name <- j[i,"name"]
    value <- j[i,"value"]
    type <- j[i,"type"]
    if (type == "INT")
      value <- as.integer(value)
    else if (type == "FLOAT")
      value <- as.double(value)
    else if (type == "BOOL")
      value <- as.logical(type.convert(value))
    values <- c(values,value)
    names <- c(names,name)
  }
  names(values) <- names
  values
}

validate_commandline <- function(args) {
  if (!is.element(args$service,c("MODEL","ROUTER","COMBINER","TRANSFORMER"))) {
    v("Invalid service type [%s]\n",args$service)
    1
  }else if (!is.element(args$api,c("REST"))) {
    v("Invalid API type [%s]\n",args$api)
    1
  }
  else{
    0
  }
}

# Parse command line and validate
args <- parse_commandline()
if (validate_commandline(args) > 0){
  quit(status=1)
}
params <- extract_parmeters(args$parameters)

# Check user model exists
if(!file.exists(args$model)){
  v("Model file does not exist [%s]\n",args$model)
  quit(status=1)
}

#Load user model
source(args$model)
user_model <- initialise_seldon(params)

# Setup generics
# Predict already exists in base R
send_feedback <- function(x,...) UseMethod("send_feedback", x)
route <- function(x,...) UseMethod("route",x)
transform_input <- function(x,...) UseMethod("transform_input",x)
transform_output <- function(x,...) UseMethod("transform_output",x)

serve_model <- plumber$new()
if (args$service == "MODEL") {
  serve_model$handle("POST", "/predict",predict_endpoint)
  serve_model$handle("GET", "/predict",predict_endpoint)
} else if (args$service == "ROUTER") {
  serve_model$handle("POST", "/route",route_endpoint)
  serve_model$handle("GET", "/route",route_endpoint)
  serve_model$handle("POST", "/send-feedback",send_feedback_endpoint)
  serve_model$handle("GET", "/send-feedback",send_feedback_endpoint)
}  else if (args$service == "TRANSFORMER") {  
  serve_model$handle("POST", "/transform-output",transform_output_endpoint)
  serve_model$handle("GET", "/transform-output",transform_output_endpoint)
  serve_model$handle("POST", "/transform-input",transform_input_endpoint)
  serve_model$handle("GET", "/transform-input",transform_input_endpoint)
  
} else
{
  v("Unknown service type [%s]\n",args$service)
  quit(status=1)
}

port <- Sys.getenv("PREDICTIVE_UNIT_SERVICE_PORT")
if (port == ''){
  port <- 5000
} else {
  port <- as.integer(port)
}
serve_model$run(host="0.0.0.0", port = port)
