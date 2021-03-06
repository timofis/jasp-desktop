#
# Copyright (C) 2013-2018 University of Amsterdam
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

TTestIndependentSamples <- function(dataset = NULL, options, perform = "run",
																		callback = function(...) 0, ...) {

	state <- .retrieveState()

	## call the common initialization function
	init <- .initializeTTest(dataset, options, perform, type = "independent-samples")

	results <- init[["results"]]
	dataset <- init[["dataset"]]

	if (length(options$variables) != 0 && options$groupingVariable != '') {
		errors <- .hasErrors(dataset, perform, type = 'factorLevels',
												 factorLevels.target = options$groupingVariable, factorLevels.amount = '!= 2',
												 exitAnalysisIfErrors = TRUE)
	}

	## call the specific independent T-Test functions
	results[["ttest"]] <- .ttestIndependentSamplesTTest(dataset, options, perform)
	descriptivesTable <- .ttestIndependentSamplesDescriptives(dataset, options, perform)
	levene <- .ttestIndependentSamplesInequalityOfVariances(dataset, options, perform)
	shapiroWilk <- .ttestIndependentSamplesNormalityTest(dataset, options, perform)
	results[["assumptionChecks"]] <- list(shapiroWilk = shapiroWilk, levene = levene, title = "Assumption Checks")


	keep <- NULL
	## if the user wants descriptive plots, s/he shall get them!
	if (options$descriptivesPlots && length(options$variables) > 0) {

		plotTitle <- ifelse(length(options$variables) > 1, "Descriptives Plots", "Descriptives Plot")
		descriptivesPlots <- .independentSamplesTTestDescriptivesPlot(dataset, options, perform)
		if (!is.null(descriptivesPlots[[1]][["obj"]])){
			keep <- unlist(lapply(descriptivesPlots, function(x) x[["data"]]),NULL)
		}
		results[["descriptives"]] <- list(descriptivesTable = descriptivesTable,
																			title = "Descriptives",
																			descriptivesPlots = list(collection = descriptivesPlots,
																															 title = plotTitle))

	} else {

		results[["descriptives"]] <- list(descriptivesTable = descriptivesTable, title = "Descriptives")

	}

	## return the results object
	if (perform == "init") {
		return(list(results=results, status="inited"))
	} else {
		return(list(results=results, status="complete",
								state = list(options = options, results = results),
								keep = keep))
	}
}


.ttestIndependentSamplesTTest <- function(dataset, options, perform) {

	ttest <- list()
	wantsEffect <- options$effectSize
	wantsDifference <- options$meanDifference
	wantsConfidenceMeanDiff <- (options$meanDiffConfidenceIntervalCheckbox &&  options$meanDifference)
	wantsConfidenceEffSize <- (options$effSizeConfidenceIntervalCheckbox && options$effectSize)
	percentConfidenceMeanDiff <- options$descriptivesMeanDiffConfidenceIntervalPercent
	percentConfidenceEffSize <- options$descriptivesEffectSizeConfidenceIntervalPercent
	## can make any combination of the following tests:
	wantsWelchs <- options$welchs
	wantsStudents <- options$students
	wantsWilcox <- options$mannWhitneyU

	## setup table for the independent samples t-test; add column test at the
	## beginning, and remove it later should the user only specify one test
	fields <- list(list(name = "v", title = "", type = "string", combine = TRUE),
								 list(name = "test", type = "string", title = "Test"),
								 list(name = "df", type = "number", format = "sf:4;dp:3"),
								 list(name = "p", type = "number", format = "dp:3;p:.001"))

	allTests <- c(wantsStudents, wantsWelchs, wantsWilcox)
	onlyTest <- sum(allTests) == 1

	title <- "Independent Samples T-Test"
	footnotes <- .newFootnotes()

	## get the right statistics for the table and, if only one test type, add footnote
	if (wantsWilcox && onlyTest) {
		.addFootnote(footnotes, symbol = "<em>Note.</em>", text = "Mann-Whitney U test.")
		testStat <- "W"
		fields <- fields[-3] # Wilcoxon's test doesn't have degrees of freedoms
	} else if (wantsWelchs && onlyTest) {
		.addFootnote(footnotes, symbol = "<em>Note.</em>", text = "Welch's t-test.")
		testStat <- "t"
	} else if (wantsStudents && onlyTest) {
		.addFootnote(footnotes, symbol = "<em>Note.</em>", text = "Student's t-test.")
		testStat <- "t"
	} else {
		testStat <- "Statistic"
	}

	ttest["title"] <- title

	## if only doing Student's / Welch's, the table should have "t" as column name
	## for the test statistic; when doing only Wilcoxon's, the name should be "W";
	## when doing both, it should be "statistic"
	fields <- append(fields, list(list(name = testStat, type = "number",
																		 format = "sf:4;dp:3")), 2)

	## add max(BF_10) from commonBF
	if (options$VovkSellkeMPR) {
		.addFootnote(footnotes, symbol = "\u002A", text = paste0("Vovk-Sellke Maximum <em>p</em>-Ratio: Based on a ",
		"two-sided <em>p</em>-value, the maximum possible odds in favor of H\u2081 over H\u2080 equals ",
		"1/(-e <em>p</em> log(<em>p</em>)) for <em>p</em> \u2264 .37 (Sellke, Bayarri, & Berger, 2001)."))
		fields[[length(fields) + 1]] <- list(name = "VovkSellkeMPR",
																				 title = "VS-MPR\u002A",
																				 type = "number",
																				 format = "sf:4;dp:3")
	}

	if (options$effectSizesType == "cohensD") {
		effSize <- "cohen"
	}	else if (options$effectSizesType == "glassD") {
		effSize <- "glass"
	} else if (options$effectSizesType == "hedgesG") {
		effSize <- "hedges"
	}

	nameOfEffectSizeParametric <- switch(effSize,
																			 cohen = "Cohen's d",
																			 glass = "Glass' delta",
																			 hedges = "Hedges' g")

	if (!wantsWilcox) {
		nameOfLocationParameter <- "Mean Difference"
		nameOfEffectSize <- nameOfEffectSizeParametric
	} else if (wantsWilcox && onlyTest) {
		nameOfLocationParameter <- "Hodges-Lehmann Estimate"
		nameOfEffectSize <- "Rank-Biserial Correlation"
	} else if (wantsWilcox && (wantsStudents || wantsWelchs)) {
		nameOfLocationParameter <-  "Location Parameter"
		nameOfEffectSize <-  "Effect Size"
	}

	## add mean difference and standard error difference
	if (wantsDifference) {
		fields[[length(fields) + 1]] <- list(name = "md", title = nameOfLocationParameter,
																				 type = "number", format = "sf:4;dp:3")
		if (!(wantsWilcox && onlyTest)) { # Only add SE Difference if not only MannWhitney is requested
			fields[[length(fields) + 1]] <- list(name = "sed", title = "SE Difference",
																					 type = "number", format = "sf:4;dp:3")
		}
	}
	if (wantsDifference && wantsWilcox && wantsStudents && wantsWelchs) {
		.addFootnote(footnotes, symbol = "<em>Note.</em>", text = paste0("For the Student t-test and Welch t-test, ",
								 "location parameter is given by mean difference; for the Mann-Whitney test, ",
								 "location parameter is given by the Hodges-Lehmann estimate."))
	} else if (wantsDifference && wantsWilcox && wantsStudents) {
		.addFootnote(footnotes, symbol = "<em>Note.</em>", text = paste0("For the Student t-test, ",
								 "location parameter is given by mean difference; for the Mann-Whitney test, ",
								 "location parameter is given by Hodges-Lehmann estimate."))
	} else if (wantsDifference && wantsWilcox && wantsWelchs) {
		.addFootnote(footnotes, symbol = "<em>Note.</em>", text = paste0("For the Welch t-test, ",
								 "location parameter is given by mean difference; for the Mann-Whitney test, ",
								 "location parameter is given by Hodges-Lehmann estimate."))
	}

	if (wantsConfidenceMeanDiff) {
		interval <- 100 * percentConfidenceMeanDiff
		title <- paste0(interval, "% CI for ", nameOfLocationParameter)

		fields[[length(fields) + 1]] <- list(name = "lowerCIlocationParameter", type = "number",
																				 format = "sf:4;dp:3", title = "Lower",
																				 overTitle = title)
		fields[[length(fields) + 1]] <- list(name = "upperCIlocationParameter", type = "number",
																				 format = "sf:4;dp:3", title = "Upper",
																				 overTitle = title)
	}

	## add Cohen's d
	if (wantsEffect) {
		fields[[length(fields) + 1]] <- list(name = "d", title = nameOfEffectSize,
																				 type = "number", format = "sf:4;dp:3")
		if (wantsWilcox) {
			if (wantsStudents || wantsWelchs) {
				.addFootnote(footnotes, symbol = "<em>Note.</em>", text = paste0("For the Mann-Whitney test, ",
									 "effect size is given by the rank biserial correlation. For the other test(s), by ",
									 nameOfEffectSizeParametric, "."))
			}
			else {
				.addFootnote(footnotes, symbol = "<em>Note.</em>", text = paste0("For the Mann-Whitney test, ",
									 "effect size is given by the rank biserial correlation."))
			}
		}
	}

	## I hope they know what they are doing! :)
	if (wantsConfidenceEffSize) {
		interval <- 100 * percentConfidenceEffSize
		title <- paste0(interval, "% CI for ", nameOfEffectSize)

		fields[[length(fields) + 1]] <- list(name = "lowerCIeffectSize", type = "number",
																				 format = "sf:4;dp:3", title = "Lower",
																				 overTitle = title)
		fields[[length(fields) + 1]] <- list(name = "upperCIeffectSize", type = "number",
																				 format = "sf:4;dp:3", title = "Upper",
																				 overTitle = title)
	}

	## add all the fields that we may or may not have added
	## in the initialization phase, remove the Test column
	ttest[["schema"]] <- list(fields = fields[-2])

	## check if we are ready to perform!
	ready <- (perform == "run" && length(options$variables) != 0
						&& options$groupingVariable != "")

	ttest.rows <- list()
	variables <- options$variables
	if (length(variables) == 0) variables <- "."

	## add a row for each variable, even before we are conducting tests
	for (variable in variables) {
		ttest.rows[[length(ttest.rows) + 1]] <- list(v = variable)
	}

	if (ready) {
		levels <- base::levels(dataset[[ .v(options$groupingVariable) ]])

		## does the user have a direction in mind?
		if (options$hypothesis == "groupOneGreater") {

			direction <- "greater"
			message <- paste0("For all tests, the alternative hypothesis specifies that group <em>", levels[1],
												"</em> is greater than group <em>", levels[2], "</em>.")
			.addFootnote(footnotes, symbol = "<em>Note.</em>", text = message)

		} else if (options$hypothesis == "groupTwoGreater") {
			direction <- "less"
			message <- paste0("For all tests, the alternative hypothesis specifies that group  <em>", levels[1],
												"</em> is less than group <em>", levels[2], "</em>.")
			.addFootnote(footnotes, symbol = "<em>Note.</em>", text = message)

		} else {
			direction <- "two.sided"
		}


		rowNo <- 1
		whichTests <- list("1" = wantsStudents, "2" = wantsWelchs, "3" = wantsWilcox)
		groupingData <- dataset[[ .v(options$groupingVariable) ]]

		## for each variable specified, run each test that the user wants
		for (variable in options$variables) {

			errors <- .hasErrors(dataset, perform, message = 'short', type = c('observations', 'variance', 'infinity'),
													 all.target = variable, all.grouping = options$groupingVariable,
													 observations.amount = '< 2')

			variableData <- dataset[[ .v(variable) ]]

			## test is a number, indicating which tests should be run
			for (test in seq_len(length(whichTests))) {

				currentTest <- whichTests[[test]]

				## don't run a test the user doesn't want
				if (!currentTest) {
					next
				}

				errorMessage <- NULL
				row.footnotes <- NULL

				if (!identical(errors, FALSE)) {
					errorMessage <- errors$message
				} else {
					## try to run the test, catching eventual errors
					row <- try(silent = FALSE, expr = {


						ciEffSize <- percentConfidenceEffSize
						ciMeanDiff <- percentConfidenceMeanDiff
						f <- as.formula(paste(.v(variable), "~",
																	.v(options$groupingVariable)))

						y <- dataset[[ .v(variable) ]]
						groups <- dataset[[ .v(options$groupingVariable) ]]

						sds <- tapply(y, groups, sd, na.rm = TRUE)
						ms <- tapply(y, groups, mean, na.rm = TRUE)
						ns <- tapply(y, groups, function(x) length(na.omit(x)))


						if (test == 3) {
							whatTest <- "Mann-Whitney"
							r <- stats::wilcox.test(f, data = dataset,
																			alternative = direction,
																			conf.int = TRUE, conf.level = ciMeanDiff, paired = FALSE)
							df <- ""
							sed <- ""
							stat <- as.numeric(r$statistic)
							m <- as.numeric(r$estimate)
							d <- abs(.clean(as.numeric(1-(2*stat)/(ns[1]*ns[2])))) * sign(m)
							# rankBis <- 1 - (2*stat)/(ns[1]*ns[2])
							wSE <- sqrt((ns[1]*ns[2] * (ns[1]+ns[2] + 1))/12)
							rankBisSE <- sqrt(4 * 1/(ns[1]*ns[2])^2 * wSE^2)
							zRankBis <- atanh(d)
							if(direction == "two.sided") {
								confIntEffSize <- sort(c(tanh(zRankBis + qnorm((1-ciEffSize)/2)*rankBisSE), tanh(zRankBis + qnorm((1+ciEffSize)/2)*rankBisSE)))
							}else if (direction == "less") {
								confIntEffSize <- sort(c(-Inf, tanh(zRankBis + qnorm(ciEffSize)*rankBisSE)))
							}else if (direction == "greater") {
								confIntEffSize <- sort(c(tanh(zRankBis + qnorm((1-ciEffSize))*rankBisSE), Inf))
							}
						} else {
							whatTest <- ifelse(test == 2, "Welch", "Student")
							r <- stats::t.test(f, data = dataset, alternative = direction,
																 var.equal = test != 2, conf.level = ciMeanDiff, paired = FALSE)

							df <- as.numeric(r$parameter)
							m <- as.numeric(r$estimate[1]) - as.numeric(r$estimate[2])
							stat <- as.numeric(r$statistic)

							num <-  (ns[1] - 1) * sds[1]^2 + (ns[2] - 1) * sds[2]^2
							sdPooled <- sqrt(num / (ns[1] + ns[2] - 2))
							if (test == 2) { # Use different SE when using Welch T test!
								sdPooled <- sqrt(((sds[1]^2) + (sds[2]^2)) / 2)
							}

							d <- "."
							if (wantsEffect) {
								# Sources are https://en.wikipedia.org/wiki/Effect_size for now.
								if (options$effectSizesType == "cohensD") {
									d <- .clean(as.numeric((ms[1] - ms[2]) / sdPooled))
								}	else if (options$effectSizesType == "glassD") {
									d <- .clean(as.numeric((ms[1] - ms[2]) / sds[2]))
									# Should give feedback on which data is considered 2.
								} else if (options$effectSizesType == "hedgesG") {
									a <- sum(ns) - 2
									logCorrection <- lgamma(a / 2) - (log(sqrt(a / 2)) + lgamma((a - 1) / 2))
									d <- .clean(as.numeric((ms[1] - ms[2]) / sdPooled)) * exp(logCorrection) # less biased / corrected version
								}

							}
							sed <-  .clean((as.numeric(r$estimate[1]) - as.numeric(r$estimate[2])) / stat)
							confIntEffSize <- c(0,0)

							if (wantsConfidenceEffSize){
								# From MBESS package by Ken Kelley, v4.6
								dfEffSize <-  ifelse(effSize == "glass", ns[2]-1, df)

								alphaLevel <- ifelse(direction == "two.sided", 1 - (ciEffSize + 1) / 2, 1 - ciEffSize)

								confIntEffSize <- .confidenceLimitsEffectSizes(ncp = d * sqrt((prod(ns)) / (sum(ns))), 
								                                               df = dfEffSize, 
								                                               alpha.lower = alphaLevel, 
								                                               alpha.upper = alphaLevel)[c(1, 3)]
								confIntEffSize <- unlist(confIntEffSize) * sqrt((sum(ns)) / (prod(ns)))
								
								if (direction == "greater") {
									confIntEffSize[2] <- Inf
								} else if (direction == "less")
									confIntEffSize[1] <- -Inf

								confIntEffSize <- sort(confIntEffSize)
							}
						}

						## if the user doesn't want a Welch's t-test,
						## give a footnote indicating if the equality of variance
						## assumption is met; seems like in this setting there is no
						## sampling plan, thus the p-value is not defined. haha!
						if (!wantsWelchs && wantsStudents) {
							levene <- car::leveneTest(variableData, groupingData, "mean")

							## arbitrary cut-offs are arbitrary
							if (!is.na(levene[1, 3]) && levene[1, 3] < 0.05) {
								error <- .messages('footnote', 'leveneSign')
								foot.index <- .addFootnote(footnotes, error)
								row.footnotes <- list(p = list(foot.index))

							}
						}

						## same for all t-tests
						p <- as.numeric(r$p.value)

						ciLow <- .clean(r$conf.int[1])
						ciUp <- .clean(r$conf.int[2])
						lowerCIeffectSize <- .clean(as.numeric(confIntEffSize[1]))
						upperCIeffectSize <- .clean(as.numeric(confIntEffSize[2]))
						# this will be the results object
						res <- list(v = variable, test = whatTest, df = df, p = p,
												md = m, d = d, lowerCIlocationParameter = ciLow, upperCIlocationParameter = ciUp,
												lowerCIeffectSize = lowerCIeffectSize, upperCIeffectSize = upperCIeffectSize,
												sed = sed, .footnotes = row.footnotes)
						res[[testStat]] <- stat
						if (options$VovkSellkeMPR){
							res[["VovkSellkeMPR"]] <- .VovkSellkeMPR(p)
						}
						res
					})

					## if there has been an error in computing the test, log it as footnote
					if (isTryError(row)) {
						errorMessage <- .extractErrorMessage(row)
					}
				}

				if (!is.null(errorMessage)) {
					## log the error in a footnote
					index <- .addFootnote(footnotes, errorMessage)
					row.footnotes <- list(t = list(index))

					row <- list(v = variable, test = "", df = "", p = "",
											md = "", d = "", lowerCIlocationParameter = "", upperCIlocationParameter = "",
											lowerCIeffectSize = "", upperCIeffectSize = "",
											sed = "", .footnotes = list(t = list(index)))
					row[[testStat]] <- .clean(NaN)
				}
				## if the user only wants more than one test
				## update the table so that it shows the "Test" and "statistic" column
				if (sum(allTests) > 1) {
					ttest[["schema"]] <- list(fields = fields)
				}

				ttest.rows[[rowNo]] <- row
				rowNo <- rowNo + 1
			}
		}

		if (effSize == "glass") {
			sdMessage <- paste0("Glass' delta uses the standard deviation of group ", names(ns[2]),
										 " of variable ", options$groupingVariable, ".")
			.addFootnote(footnotes, symbol = "<em>Note.</em>", text = sdMessage)
		}


		ttest[["footnotes"]] <- as.list(footnotes)
	}

	ttest[["data"]] <- ttest.rows
	ttest
}


.ttestIndependentSamplesDescriptives <- function(dataset, options, perform,
																								 state = NULL, diff = NULL) {
	if (options$descriptives == FALSE) return(NULL)

	descriptives = list("title" = "Group Descriptives")

	## sets up the table for the descriptives
	fields <- list(
		list(name = "variable", title = "", type = "string", combine = TRUE),
		list(name = "group", title = "Group", type = "string"),
		list(name = "N", title = "N", type = "number"),
		list(name = "mean", title = "Mean", type = "number", format = "sf:4;dp:3"),
		list(name = "sd", title = "SD", type = "number", format = "sf:4;dp:3"),
		list(name = "se", title = "SE", type = "number", format = "sf:4;dp:3")
	)

	descriptives[["schema"]] <- list(fields = fields)
	data <- list()


	## function to check if everything is alright with the options
	isAllright <- function(variable, options, state = NULL, diff = NULL) {

		# check if the variable is in the state variables
		cond1 <- !is.null(state) && variable %in% state$options$variables

		# check if either diff is true, or it's a list and descriptives,
		# and groupingVariable, missingValues are FALSE
		cond2 <- (!is.null(diff) && (is.logical(diff) && diff == FALSE) || (is.list(diff)
																																				&& !any(diff$descriptives,diff$groupingVariable, diff$missingValues)))

		cond1 && cond2
	}

	variables <- options$variables
	if (length(variables) == 0) variables <- "."

	for (variable in variables) {

		if (isAllright(variable, options, state, diff)) {

			stateDat <- state$results$descriptives$data
			descriptivesVariables <- as.character(length(stateDat))

			for (i in seq_along(stateDat))
				descriptivesVariables[i] <- stateDat[[i]]$variable

			indices <- which(descriptivesVariables == variable)
			data[[length(data) + 1]] <- stateDat[[indices[1]]]
			data[[length(data) + 1]] <- stateDat[[indices[2]]]

		} else {
			data[[length(data) + 1]] <- list(variable = variable, .isNewGroup = TRUE)
			data[[length(data) + 1]] <- list(variable = variable)
		}
	}

	## check if we are done with all this crap
	done <- (!is.null(state) &&
						 state$options$descriptives &&
						 all(variables %in% state$options$variables))

	if (done) descriptives[["status"]] <- "complete"

	groups <- options$groupingVariable

	## if we actually have to do the test, and we have a grouping variable
	if (perform == "run" && groups != "") {
		levels <- base::levels(dataset[[ .v(groups) ]])

		rowNo <- 1
		groupingData <- dataset[[.v(groups)]]

		## do the whole loop as above again
		for (variable in variables) {

			# if everything is alright, add stuff to data
			if (isAllright(variable, options, state, diff)) {

				stateDat <- state$results$descriptives$data
				descriptivesVariables <- as.character(length(stateDat))

				for (i in seq_along(stateDat))
					descriptivesVariables[i] <- stateDat[[i]]$variable

				indices <- which(descriptivesVariables == variable)

				data[[rowNo]] <- stateDat[[indices[1]]]
				data[[rowNo]] <- stateDat[[indices[2]]]

				rowNo <- rowNo + 2

			} else {

				for (i in 1:2) {

					level <- levels[i]
					variableData <- dataset[[.v(variable)]]

					groupData <- variableData[groupingData == level]
					groupDataOm <- na.omit(groupData)

					if (class(groupDataOm) != "factor") {

						n <- .clean(length(groupDataOm))
						mean <- .clean(mean(groupDataOm))
						std <- .clean(sd(groupDataOm))
						sem <- .clean(sd(groupDataOm) / sqrt(length(groupDataOm)))

						result <- list(variable = variable, group = level,
													 N = n, mean = mean, sd = std, se = sem)

					} else {

						n <- .clean(length(groupDataOm))
						result <- list(variable = variable, group = "",
													 N = n, mean = "", sd = "", se = "")
					}

					if (i == 1) {
						result[[".isNewGroup"]] <- TRUE
					}

					data[[rowNo]] <- result
					rowNo <- rowNo + 1
				}
			}
		}
		descriptives[["status"]] <- "complete"
	}

	descriptives[["data"]] <- data
	descriptives
}


.ttestIndependentSamplesInequalityOfVariances <- function(dataset, options, perform) {
	if (options$equalityOfVariancesTests == FALSE) return(NULL)

	levenes <- list("title" = "Test of Equality of Variances (Levene's)")
	footnotes <- .newFootnotes()

	## setup table for Levene's test
	fields <- list(list(name = "variable", title = "", type = "string"),
								 list(name = "F", type = "number", format = "sf:4;dp:3"),
								 list(name = "df", type = "integer"),
								 list(name = "p", type = "number", format = "dp:3;p:.001"))

	levenes[["schema"]] <- list(fields = fields)

	data <- list()
	variables <- options$variables
	groups <- options$groupingVariable
	if (length(variables) == 0) variables <- "."

	for (variable in variables) {
		data[[length(data) + 1]] <- list(variable = variable)
	}

	if (perform == "run" && groups != "") {

		levels <- base::levels(dataset[[ .v(groups) ]])

		rowNo <- 1

		for (variable in variables) {

			result <- try(silent = TRUE, expr = {

				levene <- car::leveneTest(dataset[[ .v(variable) ]],
																	dataset[[ .v(groups) ]], "mean")

				F <- .clean(levene[1, "F value"])
				df <- .clean(levene[1, "Df"])
				p <- .clean(levene[1, "Pr(>F)"])

				row <- list(variable = variable, F = F, df = df, p = p)

				if (is.na(levene[1, "F value"])) {
					note <- "F-statistic could not be calculated"
					index <- .addFootnote(footnotes, note)
					row[[".footnotes"]] <- list(F = list(index))
				}

				row
			})

			if (isTryError(result)) {
				result <- list(variable = variable, F = "", df = "", p = "")
			}

			data[[rowNo]] <- result
			rowNo <- rowNo + 1
		}
	}
	levenes[["data"]] <- data
	levenes[["footnotes"]] <- as.list(footnotes)
	levenes
}


.ttestIndependentSamplesNormalityTest <- function(dataset, options, perform) {
	if (options$normalityTests == FALSE) return(NULL)

	normalityTests <- list("title" = "Test of Normality (Shapiro-Wilk)")

	## these are the table fields associated with the normality test
	fields <- list(
		list(name = "dep", type = "string", title = "", combine = TRUE),
		list(name = "lev", type = "string", title = ""),
		list(name = "W", title = "W", type = "number", format = "sf:4;dp:3"),
		list(name = "p", title = "p", type = "number", format = "dp:3;p:.001")
	)

	normalityTests[["schema"]] <- list(fields = fields)

	footnotes <- .newFootnotes()
	.addFootnote(footnotes, symbol = "<em>Note.</em>",
							 text = "Significant results suggest a deviation from normality.")

	## for a independent t-test, we need to check both group vectors for normality
	normalityTests.results <- list()

	variables <- options$variables
	factor <- options$groupingVariable
	levels <- levels(dataset[[.v(factor)]])

	if (length(variables) == 0) variables = "."
	if (length(levels) == 0) levels = c(".", ".")

	for (variable in variables) {
		count <- 0

		## there will be maximal two levels
		for (level in levels) {
			count <- count + 1

			## if everything looks fine, and we are ready to run
			if (perform == "run" && length(variables) > 0 && !is.null(levels) && factor != "") {

				## get the dependent variable at a certain factor level
				data <- na.omit(dataset[[.v(variable)]][dataset[[.v(factor)]] == level])

				row.footnotes <- NULL
				error <- FALSE

				errors <- .hasErrors(dataset, perform, message = 'short', type = c('observations', 'variance', 'infinity'),
														 all.target = variable,
														 observations.amount = c('< 3', '> 5000'),
														 all.grouping = factor,
														 all.groupingLevel = level)

				if (!identical(errors, FALSE)) {
					errorMessage <- errors$message
					foot.index <- .addFootnote(footnotes, errorMessage)
					row.footnotes <- list(W = list(foot.index), p = list(foot.index))
					error <- TRUE
				}

				## if the user did everything correctly :)
				if (!error) {
					r <- stats::shapiro.test(data)
					W <- .clean(as.numeric(r$statistic))
					p <- .clean(r$p.value)

					## if that's the first variable, add a new row
					newGroup <- level == levels[1]
					result <- list(dep = variable, lev = level,
												 W = W, p = p, .isNewGroup = newGroup)

					## if there was a problem, foonote it
				} else {

					newGroup <- level == levels[1]
					result <- list(dep = variable, lev = level,
												 W = "NaN", p = "NaN", .isNewGroup = newGroup,
												 .footnotes = row.footnotes)
				}

				## if we are not yet ready to perform
				## create an empty table for immediate feedback
			} else {

				newGroup <- count == 1
				result <- list(dep = variable, lev = level,
											 W = ".", p = ".", .isNewGroup = newGroup)
			}
			normalityTests.results[[length(normalityTests.results) + 1]] <- result
		}
	}

	normalityTests[["data"]] <- normalityTests.results
	normalityTests[["footnotes"]] <- as.list(footnotes)
	normalityTests
}


.independentSamplesTTestDescriptivesPlot <- function(dataset, options, perform) {

	variables <- options$variables
	groups <- options$groupingVariable

	descriptivesPlotList <- list()

	if (perform == "run" && length(variables) > 0 && groups != "") {

		base_breaks_x <- function(x) {
			b <- unique(as.numeric(x))
			d <- data.frame(y = -Inf, yend = -Inf, x = min(b), xend = max(b))
			list(ggplot2::geom_segment(data = d, ggplot2::aes(x = x, y = y, xend = xend,
																												yend = yend), inherit.aes = FALSE, size = 1))
		}

		base_breaks_y <- function(x) {
			ci.pos <- c(x[, "dependent"] - x[, "ci"], x[, "dependent"] + x[, "ci"])
			b <- pretty(ci.pos)
			d <- data.frame(x = -Inf, xend = -Inf, y = min(b), yend = max(b))
			list(ggplot2::geom_segment(data = d, ggplot2::aes(x = x, y = y,xend = xend,
																												yend = yend), inherit.aes = FALSE, size = 1),
					 ggplot2::scale_y_continuous(breaks = c(min(b), max(b))))
		}

		for (variableIndex in .indices(variables)) {

			descriptivesPlot <- list("title" = variables[variableIndex])

			errors <- .hasErrors(dataset, perform, message = 'short', type = c('observations', 'variance', 'infinity'),
													 all.target = variables[variableIndex],
													 observations.amount = '< 2',
													 observations.grouping = options$groupingVariable)

			if (!identical(errors, FALSE)) {
				errorMessage <- errors$message

				descriptivesPlot[["data"]] <- ""
				descriptivesPlot[["error"]] <- list(error="badData", errorMessage=errorMessage)
			} else {

				descriptivesPlot[["width"]] <- options$plotWidth
				descriptivesPlot[["height"]] <- options$plotHeight
				descriptivesPlot[["custom"]] <- list(width = "plotWidth", height = "plotHeight")

				dataset <- na.omit(dataset)

				summaryStat <- .summarySE(as.data.frame(dataset), measurevar = .v(options$variables[variableIndex]),
																	groupvars = .v(options$groupingVariable), conf.interval = options$descriptivesPlotsConfidenceInterval,
																	na.rm = TRUE, .drop = FALSE)

				colnames(summaryStat)[which(colnames(summaryStat) == .v(variables[variableIndex]))] <- "dependent"
				colnames(summaryStat)[which(colnames(summaryStat) == .v(groups))] <- "groupingVariable"

				pd <- ggplot2::position_dodge(0.2)

				p <- ggplot2::ggplot(summaryStat, ggplot2::aes(x = groupingVariable,
																											 y = dependent, group = 1)) + ggplot2::geom_errorbar(ggplot2::aes(ymin = ciLower,
																																																												ymax = ciUpper), colour = "black", width = 0.2, position = pd) +
					ggplot2::geom_line(position = pd, size = 0.7) + ggplot2::geom_point(position = pd,
																																							size = 4) + ggplot2::ylab(unlist(options$variables[variableIndex])) + ggplot2::xlab(options$groupingVariable) +
					base_breaks_y(summaryStat) + base_breaks_x(summaryStat$groupingVariable)

				p <- JASPgraphs::themeJasp(p)

				imgObj <- .writeImage(width = options$plotWidth,
															height = options$plotHeight,
															plot = p)

				descriptivesPlot[["data"]] <- imgObj[["png"]]
				descriptivesPlot[["obj"]] <- imgObj[["obj"]]

			}

			descriptivesPlot[["convertible"]] <- TRUE
			descriptivesPlot[["status"]] <- "complete"

			descriptivesPlotList[[variableIndex]] <- descriptivesPlot

		}

		return(descriptivesPlotList)

	} else {

		return(NULL)

	}

}


.confidenceLimitsEffectSizes <- function(ncp, df, conf.level=.95, alpha.lower=NULL, alpha.upper=NULL, t.value, 
                                         tol=1e-9, ...) {
	# This function comes from the MBESS package, version 4.6, by Ken Kelley
	# https://cran.r-project.org/web/packages/MBESS/index.html
	# Note this function is new in version 4, replacing what was used in prior versions.
	# Internal functions for the noncentral t distribution; two appraoches.
	###########


	# General stop checks.
	if(!is.null(conf.level) & is.null(alpha.lower) & is.null(alpha.upper)) {
		alpha.lower <- (1 - conf.level) / 2
		alpha.upper <- (1 - conf.level) / 2
	}


	.conf.limits.nct.M1 <- function(ncp, df, conf.level=NULL, alpha.lower, alpha.upper, tol=1e-9, ...) {

		min.ncp <- min(-150, -5 * ncp)
		max.ncp <- max(150, 5 * ncp)

		# Internal function for upper limit.
		# Note the upper tail is used here, as we seek to find the NCP that has, in its upper tail (alpha.lower, 
		# for the lower limit), the specified value of the observed t/ncp.
		###########################
		
		.ci.nct.lower <- function(val.of.interest, ...) {
			(qt(p=alpha.lower, df=df, ncp=val.of.interest, lower.tail = FALSE, log.p = FALSE) - ncp)^2
		}
		###########################

		# Internal function for lower limit.
		# Note the lower tail is used here, as we seek to find the NCP that has, in its lower tail (alpha.upper, 
		# for the upper limit), the specified value of the observed t/ncp.
		###########################
		.ci.nct.upper <- function(val.of.interest, ...) {
			(qt(p=alpha.upper, df=df, ncp=val.of.interest, lower.tail = TRUE, log.p = FALSE) - ncp)^2
		}

		if(alpha.lower!=0) {
		  Low.Lim <- suppressWarnings(optimize(f=.ci.nct.lower, interval=c(min.ncp, max.ncp),
		                                       alpha.lower=alpha.lower, df=df, ncp=ncp, 
			                                     maximize=FALSE, tol=tol))
		}

		if(alpha.upper!=0) {
			Up.Lim <- suppressWarnings(optimize(f=.ci.nct.upper, interval=c(min.ncp, max.ncp), 
			                                    alpha.upper=alpha.upper, df=df, ncp=ncp, 
			                                    maximize=FALSE, tol=tol))
		}

		if(alpha.lower==0) Result <- list(Lower.Limit=-Inf, Prob.Less.Lower=0, Upper.Limit=Up.Lim$minimum, 
		                                  Prob.Greater.Upper=pt(q=ncp, ncp=Up.Lim$minimum, df=df))
		if(alpha.upper==0) Result <- list(Lower.Limit=Low.Lim$minimum, 
		                                  Prob.Less.Lower=pt(q=ncp, ncp=Low.Lim$minimum, df=df, lower.tail=FALSE), 
		                                  Upper.Limit=Inf, Prob.Greater.Upper=0)
		if(alpha.lower!=0 & alpha.upper!=0) Result <- list(Lower.Limit=Low.Lim$minimum, 
		                                                   Prob.Less.Lower=pt(q=ncp, ncp=Low.Lim$minimum, df=df, 
		                                                                      lower.tail=FALSE), 
		                                                   Upper.Limit=Up.Lim$minimum, 
		                                                   Prob.Greater.Upper=pt(q=ncp, ncp=Up.Lim$minimum, df=df))

		return(Result)
	}
	################################################
	.conf.limits.nct.M2 <- function(ncp, df, conf.level=NULL, alpha.lower, alpha.upper, tol=1e-9, ...) {

		# Internal function for upper limit.
		###########################
		.ci.nct.lower <- function(val.of.interest, ...) {
			(qt(p=alpha.lower, df=df, ncp=val.of.interest, lower.tail = FALSE, log.p = FALSE) - ncp)^2
		}

		# Internal function for lower limit.
		###########################
		.ci.nct.upper <- function(val.of.interest, ...) {
			(qt(p=alpha.upper, df=df, ncp=val.of.interest, lower.tail = TRUE, log.p = FALSE) - ncp)^2
		}

		Low.Lim <- suppressWarnings(nlm(f=.ci.nct.lower, p=ncp, ...))
		Up.Lim <- suppressWarnings(nlm(f=.ci.nct.upper, p=ncp, ...))


		if(alpha.lower==0) Result <- list(Lower.Limit=-Inf, Prob.Less.Lower=0, Upper.Limit=Up.Lim$estimate, 
		                                  Prob.Greater.Upper=pt(q=ncp, ncp=Up.Lim$estimate, df=df))
		if(alpha.upper==0) Result <- list(Lower.Limit=Low.Lim$estimate, 
		                                  Prob.Less.Lower=pt(q=ncp, ncp=Low.Lim$estimate, df=df, lower.tail=FALSE), 
		                                  Upper.Limit=Inf, Prob.Greater.Upper=0)
		if(alpha.lower!=0 & alpha.upper!=0) Result <- list(Lower.Limit=Low.Lim$estimate, 
		                                                   Prob.Less.Lower=pt(q=ncp, ncp=Low.Lim$estimate, df=df, 
		                                                                      lower.tail=FALSE), 
		                                                   Upper.Limit=Up.Lim$estimate, 
		                                                   Prob.Greater.Upper=pt(q=ncp, ncp=Up.Lim$estimate, df=df))

		return(Result)
	}

	# Now, use the each of the two methods.
	Res.M1 <- Res.M2 <- NULL
	try(Res.M1 <- .conf.limits.nct.M1(ncp=ncp, df=df, conf.level=NULL, alpha.lower=alpha.lower, 
	                                  alpha.upper=alpha.upper, tol=tol), silent=TRUE)
	if(length(Res.M1)!=4) Res.M1 <- NULL

	try(Res.M2 <- .conf.limits.nct.M2(ncp=ncp, df=df, conf.level=NULL, alpha.lower=alpha.lower,
	                                  alpha.upper=alpha.upper, tol=tol), silent=TRUE)
	if(length(Res.M2)!=4) Res.M2 <- NULL

	# Now, set-up the test to find the best method.
	Low.M1 <- Res.M1$Lower.Limit
	Prob.Low.M1 <- Res.M1$Prob.Less.Lower
	Upper.M1 <- Res.M1$Upper.Limit
	Prob.Upper.M1 <- Res.M1$Prob.Greater.Upper

	Low.M2 <- Res.M2$Lower.Limit
	Prob.Low.M2 <- Res.M2$Prob.Less.Lower
	Upper.M2 <- Res.M2$Upper.Limit
	Prob.Upper.M2 <- Res.M2$Prob.Greater.Upper

	# Choose the best interval limits:
	##Here low
	Min.for.Best.Low <- min((c(Prob.Low.M1, Prob.Low.M2)-alpha.lower)^2)

	if(!is.null(Res.M1)){if(Min.for.Best.Low==(Prob.Low.M1-alpha.lower)^2) Best.Low <- 1}
	if(!is.null(Res.M2)){if(Min.for.Best.Low==(Prob.Low.M2-alpha.lower)^2) Best.Low <- 2}

	##Here high
	Min.for.Best.Up <- min((c(Prob.Upper.M1, Prob.Upper.M2)-alpha.upper)^2)

	if(!is.null(Res.M1)){if(Min.for.Best.Up==(Prob.Upper.M1-alpha.upper)^2) Best.Up <- 1}
	if(!is.null(Res.M2)){if(Min.for.Best.Up==(Prob.Upper.M2-alpha.upper)^2) Best.Up <- 2}
	#####################################

	if(is.null(Res.M1)) {Low.M1 <- NA; Prob.Low.M1 <- NA; Upper.M1 <- NA; Prob.Upper.M1 <- NA}
	if(is.null(Res.M2)) {Low.M2 <- NA; Prob.Low.M2 <- NA; Upper.M2 <- NA; Prob.Upper.M2 <- NA}

	Result <- list(Lower.Limit=c(Low.M1, Low.M2)[Best.Low], 
	               Prob.Less.Lower=c(Prob.Low.M1, Prob.Low.M2)[Best.Low], 
	               Upper.Limit=c(Upper.M1, Upper.M2)[Best.Up], 
	               Prob.Greater.Upper=c(Prob.Upper.M1, Prob.Upper.M2)[Best.Up])

	return(Result)
}
