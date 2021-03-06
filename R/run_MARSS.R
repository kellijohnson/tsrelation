#' Calculate estimates from a MARSS model
#'
#' @details Run a multivariate-autoregressive state-space (MARSS) model.
#' The model structure assumes that there are two time series available,
#' where the attribute affects the indicator. The magnitude of this affect
#' will be estimated using the $B$ matrix in the off-diagonal lower element.
#' The MARSS model is ran using \code{\link[MARSS]{MARSS}}.
#' Warning messages from \code{\link[MARSS]{MARSS}} are suppressed using
#' \code{sink} and \code{\link[base]{tryCatch}}.
#'
#' @param data A \code{data.frame} with two columns,
#' where the first column is the attribute and the second column is the
#' indicator, or the dependent variable. The columns need not be named.
#' @param MARSScntliterations An integer value specifying the maximum number of
#' iterations to run in the estimation model.
#' @param MARSSbootn An integer value specifying the number of bootstrap
#' iterations to run generating the confidence intervals.
#' @param B Specifications for interactions in the estimation method.
#' @param Q Specifications for process error in the estimation method.
#' @param U Specifications for intercepts in the estimation method.
#' @param Z Specifications for observations to hidden states
#' in the estimation method.
#' @param R Specifications for observation error in the estimation method.
#' @param A Specifications for scaling matrix in the estimation method.
#'
#' @return A list object is returned with the model results and names of
#' the attributes and indicators, along with the original data used to run
#' the model and a status indicator providing information on if the model was
#' ran (i.e., "good") or not (i.e., "bad").
#' @author Kelli Faye Johnson
#' @export
#'
run_MARSS <- function(data, MARSScntliterations = 500,
  MARSSbootn = 100, #MARSSbootn = 20,
  B, Q, U = "zero", Z, R, A = NULL) {

  if (B == "fixed") B <- matrix(list("a:a", "i:a", 0, "i:i"), 2)
  Q <- ifelse(Q == "equal", "diagonal and equal", Q)
  Q <- ifelse(Q == "unequal", "diagonal and unequal", Q)
  R <- ifelse(R == "equal", "diagonal and equal", R)
  R <- ifelse(R == "unequal", "diagonal and unequal", R)
  if(is.null(A)) A <- matrix(0, NCOL(data), 1)
  if (!is.factor(Z)) Z <- factor(Z)

  if (length(levels(Z)) != 2) stop("Two unique values must ",
    "be specified in Z")

  # Control variables for the MARSS model
  cntl <- list(allow.degen = FALSE, maxit = MARSScntliterations,
    safe = TRUE, trace = -1)

  model <- list(
    B = B,
    U = U, # b/c the data are z-scored U should ~ == 0
    Q = Q, # Proc error ~MVN(0,Q)
    Z = Z,
    A = A,
    R = R, # Obs error ~MVN(0,R)
    # tinitx = 1, # Initial state of time-step 0 (default) or 1
    # x0 = "zero",
    V0 = "zero" # default is zero x(0) ~ MVN(x0, V0)
    )

  e <- simpleError("MARSS sucks")
  data_model <- t(data)
  if(all.equal(data[, 1], data[, 2], tolerance = 1e-9) == TRUE) return(NULL)
  ci <- tryCatch(
    MARSS::MARSS(data_model, model = model, control = cntl,
    silent = TRUE, fit = TRUE, method = "kem"),
    error = function(e) e)
  if (!any(c("error", "try-error") %in% class(ci))) {
    ci <- suppressWarnings(try(
      MARSS::MARSSparamCIs(ci, method = "parametric", nboot = MARSSbootn),
      silent = TRUE))
    if (!"try-error" %in% class(ci)) {
      if (any(unlist(lapply(ci$par.se, is.na)))) ci$convergence <- 111
    } else {
      return(NULL)
    }
  } else return(NULL)

  # Need to fit another model without the correlation in the process errors
  # to do a likelihood ratio test.
  model2 <- model
  model2$Q <- "diagonal and unequal"
  otherem <- tryCatch(
    MARSS::MARSS(data_model, model = model2,
      control = cntl, silent = TRUE, fit = TRUE, method = "kem"),
    error = function(e) e)
  # Perform the likelihood ratio test
  if (!any(c("error", "try-error") %in% class(ci))) {
    lrt <- pchisq(ci$logLik*-2-otherem$logLik*-2, 1, lower.tail = FALSE)
    ppp <- 2 * (ci$logLik - otherem$logLik)
    lrt <- pchisq(ppp, 1, lower.tail = FALSE)
    ci$likelihoodratiotest <- lrt
  } else {ci$likelihoodratiotest <- 1}

  return("marss" = ci)
}

