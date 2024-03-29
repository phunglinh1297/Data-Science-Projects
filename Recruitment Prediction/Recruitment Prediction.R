knitr::opts_chunk$set(echo = TRUE)

library("adabag")
library(caret)
library(dplyr)
library(gbm)
library(xgboost)
library(recipes)
library(DiagrammeR)
library(pROC)

## Import data ----
recruit <- read.csv("Placement_Data_Full_Class.csv")
# drop salary & sl_no
recruit <- recruit[,!colnames(recruit) %in% c("salary","sl_no")]

## Descriptive analysis ----
# check Y balance and NA
prop.table(table(recruit[,'status'])) # 31 no, 69 yes not heavily imbalanced
recruit[is.na(recruit) == TRUE,]

# turn categorical X to factors
data <- recruit %>% mutate_if(is.character, as.factor)
str(data)
factor(data$status)

## Split data ----
# Create the training and test datasets
set.seed(777)
# Step 1: Get row numbers for the training data
dbRowNumbers <- createDataPartition(data$status, p=0.7, list=FALSE)
# Step 2: Create the training  dataset
train_data <- data[dbRowNumbers,]
# Step 3: Create the test dataset 
test_data <- data[-dbRowNumbers,]

# set up 5-fold cross validation procedure
train_control <- trainControl(method = "cv", number = 5)
Grid = expand.grid(mfinal=seq(1,300,10), maxdepth = 1, coeflearn="Breiman")

# train adaptive boosting model 
set.seed(777)
ada_model <- train(train_data[,-13],train_data[,13]
                      , method = "AdaBoost.M1", trControl = train_control
                      , tuneGrid = Grid)
# plot mfinal vs Accuracy => best tune when accuracy is highest
plot(ada_model$results$mfinal, ada_model$results$Accuracy,
     type = "l", col = "blue", lwd = 2,
     xlab = "Number of Final Trees (mfinal)",
     ylab = "Accuracy",
     main = "Accuracy vs. mfinal in AdaBoost")

set.seed(777)
ada_model$results
# Predict on testing set using Adaboost
ada_pred <- predict(ada_model$finalModel,test_data[,-13])
# Confusion matrix 
result1 <- table(ada_pred$class,test_data[,"status"])
confusion_matrix <- confusionMatrix(result1, positive = "Placed")
confusion_matrix
#NOTE: Accuracy 84%

# set up grid search
train_control2 <- trainControl(method = "cv", number = 5)
Grid2 = expand.grid(n.trees=seq(100,10000,100), interaction.depth = c(1,3,5)
                   , shrinkage = seq(0.05,0.3,0.01), n.minobsinnode = c(5,10,15))
#modelLookup("gbm")

# train Gradient Boosting model
set.seed(123)
gbm_model <- train(train_data[,-13],train_data[,13]
                   , method = "gbm", trControl = train_control2
                   , tuneGrid = Grid2)
# check top 10 models
top10 <- data.frame(gbm_model$results)
top10 <- top10[order(-top10$Accuracy), ]
head(top10,10)

# adjust gridSearch based on top 10 models
set.seed(123)
Grid3 = expand.grid(n.trees=seq(1000,5000,100), interaction.depth = c(3,5)
                    , shrinkage = seq(0.08,0.3,0.01), n.minobsinnode = seq(5,10,1))
gbm_model_final <- train(train_data[,-13],train_data[,13]
                   , method = "gbm", trControl = train_control2
                   , tuneGrid = Grid3)
gbm_model_final$bestTune

# Predict on testing set using Gradient Boosting
gbm_pred <- predict(gbm_model_final,test_data[,-13])
# Confusion matrix 
result2 <- table(gbm_pred,test_data[,"status"])
confusion_matrix2 <- confusionMatrix(result2, positive = "Placed")
confusion_matrix2
#NOTE: Accuracy = 83%

# convert character variables to numerical variables using label encoding
set.seed(777)
xgb_prep <- recipe(status ~ ., data = train_data) %>%
  step_integer(all_nominal()) %>%
  prep(training = train_data, retain = TRUE) %>%
  juice()
x_train <- as.matrix(xgb_prep[setdiff(names(xgb_prep), "status")])
# ensure Placed = 1, and Not placed = 0
y_train <- xgb_prep$status -1

# set gridSearch
train_control4 <- trainControl(method = "cv", number = 5)

# hyperparameter grid
hyper_grid <- expand.grid(
  eta = seq(0.01,0.3,by=0.02),
  max_depth = c(1,3,5), 
  min_child_weight = c(1,3,5,7),
  subsample = seq(0.5,0.9,by=0.1), 
  colsample_bytree = seq(0.5,0.9,by=0.1),
  gamma = 0, # start with 0 first and check train error vs test error
  lambda = 0,
  alpha = 0,
  error = 0,          # a place to dump results
  trees = 0          # a place to dump required number of trees
)

# train Gradient Boosting parameters using CV grid search
for(i in seq_len(nrow(hyper_grid))) {
  set.seed(123)
  m <- xgb.cv(
    data = x_train,
    label = y_train,
    nrounds = 5000,
    objective = "binary:logistic",
    early_stopping_rounds = 100, 
    nfold = 5,
    verbose = 1,
    allowParallel = TRUE, # allow for prarallel processing (to speed up computations)
    eval_metric = "error",
    params = list( 
      eta = hyper_grid$eta[i], 
      max_depth = hyper_grid$max_depth[i],
      min_child_weight = hyper_grid$min_child_weight[i],
      subsample = hyper_grid$subsample[i],
      colsample_bytree = hyper_grid$colsample_bytree[i],
      gamma = hyper_grid$gamma[i], 
      lambda = hyper_grid$lambda[i], 
      alpha = hyper_grid$alpha[i]
    ) 
  )
  hyper_grid$error[i] <- min(m$evaluation_log$test_error_mean)
  hyper_grid$trees[i] <- m$best_iteration
}
# check top 20
head(hyper_grid[order(hyper_grid$error), ],20)

# hyperparameter grid
hyper_grid2 <- expand.grid(
  eta = seq(0.1,0.3,by=0.02),
  max_depth = c(3,5), 
  min_child_weight = c(1,3),
  subsample = seq(0.7,0.9,by=0.1), 
  colsample_bytree = seq(0.6,0.9,by=0.1),
  gamma = 0, # start with 0 first and check train error vs test error
  lambda = 0,
  alpha = 0,
  te_error = 0, # a place to dump results
  tr_error = 0,
  trees = 0          # a place to dump required number of trees
)

# train Gradient Boosting parameters using CV grid search
for(i in seq_len(nrow(hyper_grid2))) {
  set.seed(777)
  m2 <- xgb.cv(
    data = x_train,
    label = y_train,
    nrounds = 1000,
    objective = "binary:logistic",
    early_stopping_rounds = 50, 
    nfold = 5,
    verbose = 1,
    allowParallel = TRUE, # allow for prarallel processing (to speed up computations)
    eval_metric = "error",
    params = list( 
      eta = hyper_grid2$eta[i], 
      max_depth = hyper_grid2$max_depth[i],
      min_child_weight = hyper_grid2$min_child_weight[i],
      subsample = hyper_grid2$subsample[i],
      colsample_bytree = hyper_grid2$colsample_bytree[i],
      gamma = hyper_grid2$gamma[i], 
      lambda = hyper_grid2$lambda[i], 
      alpha = hyper_grid2$alpha[i]
    ) 
  )
  hyper_grid2$te_error[i] <- min(m2$evaluation_log$test_error_mean)
  hyper_grid2$tr_error[i] <- min(m2$evaluation_log$train_error_mean)
  hyper_grid2$trees[i] <- m2$best_iteration
}
# check top 20
head(hyper_grid2[order(hyper_grid2$te_error), ],20)

# hyperparameter grid
hyper_grid3 <- expand.grid(
  eta = seq(0.1,0.3,by=0.02),
  max_depth = c(3,5), 
  min_child_weight = c(1,3),
  subsample = seq(0.7,0.9,by=0.1), 
  colsample_bytree = seq(0.6,0.9,by=0.1),
  gamma = c(0.1,1,10), 
  lambda = c(0.1,1,10),
  alpha = c(0.1,1,10),
  te_error = 0, # a place to dump results
  tr_error = 0,
  trees = 0 # a place to dump required number of trees
)

# train Gradient Boosting parameters using CV grid search
for(i in seq_len(nrow(hyper_grid3))) {
  set.seed(777)
  m3 <- xgb.cv(
    data = x_train,
    label = y_train,
    nrounds = 1000,
    objective = "binary:logistic",
    early_stopping_rounds = 50, 
    nfold = 5,
    verbose = 1,
    allowParallel = TRUE, # allow for prarallel processing (to speed up computations)
    eval_metric = "error",
    params = list( 
      eta = hyper_grid3$eta[i], 
      max_depth = hyper_grid3$max_depth[i],
      min_child_weight = hyper_grid3$min_child_weight[i],
      subsample = hyper_grid3$subsample[i],
      colsample_bytree = hyper_grid3$colsample_bytree[i],
      gamma = hyper_grid3$gamma[i], 
      lambda = hyper_grid3$lambda[i], 
      alpha = hyper_grid3$alpha[i]
    ) 
  )
  hyper_grid3$te_error[i] <- min(m3$evaluation_log$test_error_mean)
  hyper_grid3$tr_error[i] <- min(m3$evaluation_log$train_error_mean)
  hyper_grid3$trees[i] <- m3$best_iteration
}
# check top 20
head(hyper_grid3[order(hyper_grid3$te_error), ],20)

# label encoding for categorical variables for testing set
set.seed(777)
xgb_test <- recipe(status ~ ., data = test_data) %>%
  step_integer(all_nominal()) %>%
  prep(training = test_data, retain = TRUE) %>%
  juice()
x_test <- as.matrix(xgb_test[setdiff(names(xgb_test), "status")])
# ensure Placed = 1, and Not placed = 0
y_test <- xgb_test$status -1 

# Case 1: WITHOUT regularisation (2nd try)
# optimal parameter list
set.seed(777)
xg_params <- list(
  eta = 0.18,
  max_depth = 3,
  min_child_weight = 3,
  subsample = 0.7,
  colsample_bytree = 0.8)
# train final model
xgb.fit.final <- xgboost(
  params = xg_params,
  data = x_train,
  label = y_train,
  nrounds = 32,
  objective = "binary:logistic",
  gamma = 0, lambda = 0, alpha = 0,
  verbose = 0)

# Predict on testing set using xgboost
set.seed(777)
xgb_pred <- data.frame(predict(xgb.fit.final,x_test))
xgb_pred_result <- ifelse(xgb_pred>0.5,1,0)
# Confusion matrix 
result3 <- table(xgb_pred_result,y_test)
confusion_matrix3 <- confusionMatrix(result3, positive = "1")
confusion_matrix3

# Case 2: WITH Regularisation (3rd try)
# optimal parameter list
set.seed(777)
xg_params_re <- list(
  eta = 0.22,
  max_depth = 3,
  min_child_weight = 3,
  subsample = 0.7,
  colsample_bytree = 0.9)
# train final model
xgb.fit.final.re <- xgboost(
  params = xg_params_re,
  data = x_train,
  label = y_train,
  nrounds = 24,
  objective = "binary:logistic",
  gamma = 0.1, lambda = 0.1, alpha = 0.1,
  verbose = 0)

# Predict on testing set using xgboost
set.seed(777)
xgb_pred_re <- data.frame(predict(xgb.fit.final.re,x_test))
xgb_pred_result_re <- ifelse(xgb_pred_re>0.5,1,0)
# Confusion matrix 
result4 <- table(xgb_pred_result_re,y_test)
confusion_matrix4 <- confusionMatrix(result4, positive = "1")
confusion_matrix4
# NOTE: Using regularisation increases Accuracy from 84% to 89%, note that the gap between testing error on training set (validation error) and testing error on testing set is smaller for xgboost => model predicts unseen data better

# 3. Further demonstration for xgboost
# Plotting trees (first 3 trees)
xgb.plot.tree(model = xgb.fit.final.re, trees = 1:3)

# Predict probabilities using xgboost
xgb_prob <- predict(xgb.fit.final, x_test, type = "prob")
xgb_prob_re <- predict(xgb.fit.final.re, x_test, type = "prob")

# Create ROC curves
roc_obj <- roc(y_test, xgb_prob)
roc_obj_re <- roc(y_test, xgb_prob_re)

# Plot ROC curves
plot(roc_obj, col = "blue", lwd = 2, main = "ROC Curves")
lines(roc_obj_re, col = "red", lwd = 2)
legend("bottomright", legend = c("Without Regularization", "With Regularization"),
       col = c("blue", "red"), lwd = 2)

# Compute error rates
ada_error_rate <- confusion_matrix$overall['Accuracy']
xgb_error_rate1 <- confusion_matrix3$overall['Accuracy']
xgb_error_rate <- confusion_matrix4$overall['Accuracy']

# Combine error rates into a data frame
error_rates <- data.frame(
  Model = c("AdaBoost", "XGBoost (Without Regularisation)", "XGBoost (With Regularisation"),
  ErrorRate = c(ada_error_rate, xgb_error_rate1, xgb_error_rate)
)

# Plot error rates
library(ggplot2)
ggplot(error_rates, aes(x = Model, y = ErrorRate, fill = Model)) +
  geom_bar(stat = "identity", color = "black") +
  theme_minimal() +
  labs(title = "Accuracy of AdaBoost, XGBoost with/without Regularisation Models",
       x = "Model",
       y = "Accuracy") +
  theme(legend.position = "none")



#ιnitialize vectors to store results
num_trees <- seq(1, 300, 10)
ada_error_rates <- numeric(length(num_trees))
gbm_error_rates <- numeric(length(num_trees))
xgb_error_rates <- numeric(length(num_trees))
#train & record error rates
for (i in seq_along(num_trees)) {
  # AdaBoost
  Grid <- expand.grid(mfinal = num_trees[i], maxdepth = 1, coeflearn = "Breiman")
  ada_model <- train(train_data[,-13], train_data[,13],
                     method = "AdaBoost.M1", trControl = train_control,
                     tuneGrid = Grid)
  ada_pred <- predict(ada_model, test_data[,-13])
  result <- table(ada_pred, test_data[,"status"])
  confusion_matrix <- confusionMatrix(result, positive = "Placed")
  ada_error_rates[i] <- confusion_matrix$overall['Accuracy']
  
  # GBM (without regularisation)
  xg_params <- list(
  eta = 0.18,
  max_depth = 3,
  min_child_weight = 3,
  subsample = 0.7,
  colsample_bytree = 0.8)
  # train final model
  xgb.fit.final <- xgboost(
  params = xg_params,
  data = x_train,
  label = y_train,
  nrounds = 32,
  objective = "binary:logistic",
  gamma = 0, lambda = 0, alpha = 0,
  verbose = 0)
  xgb_pred <- data.frame(predict(xgb.fit.final,x_test))
  xgb_pred_result <- ifelse(xgb_pred>0.5,1,0)
  # Confusion matrix 
  result3 <- table(xgb_pred_result,y_test)
  confusion_matrix3 <- confusionMatrix(result3, positive = "1")
  gbm_error_rates[i] <- confusion_matrix3$overall['Accuracy']
  
  # XGB (with regularisation)
  xg_params_re <- list(
  eta = 0.22,
  max_depth = 3,
  min_child_weight = 3,
  subsample = 0.7,
  colsample_bytree = 0.9)
  # train final model
  xgb.fit.final.re <- xgboost(
  params = xg_params_re,
  data = x_train,
  label = y_train,
  nrounds = 24,
  objective = "binary:logistic",
  gamma = 0.1, lambda = 0.1, alpha = 0.1,
  verbose = 0)
  xgb_pred_re <- data.frame(predict(xgb.fit.final.re, x_test))
  xgb_pred_result_re <- ifelse(xgb_pred_re > 0.5, 1, 0)
  result4 <- table(xgb_pred_result_re, y_test)
  confusion_matrix4 <- confusionMatrix(result4, positive = "1")
  xgb_error_rates[i] <- confusion_matrix4$overall['Accuracy']
}
# error rates into a data frame
error_rates <- data.frame(
  NumTrees = num_trees,
  AdaBoost = ada_error_rates,
  GBM = gbm_error_rates,
  XGB = xgb_error_rates
)
#plot error rates for each model to the number of trees up to 300 (too many computations)
library(ggplot2)
ggplot(error_rates, aes(x = NumTrees)) +
  geom_line(aes(y = AdaBoost, color = "AdaBoost")) +
  geom_line(aes(y = GBM, color = "GBM")) +
  geom_line(aes(y = XGB, color = "XGB")) +
  labs(title = "Test Classification Error vs. Number of Trees",
       x = "Number of Trees",
       y = "Test Classification Error") +
  scale_color_manual(values = c("AdaBoost" = "blue", "GBM" = "red", "XGB" = "green")) +
  theme_minimal()

# Get the feature real names
names <- dimnames(data.matrix(x_train[,-13]))[[2]]
# Compute feature importance matrix
importance_matrix <- xgb.importance(names, model = xgb.fit.final.re)
# Nice graph
xgb.plot.importance(importance_matrix, measure = "Gain")
#NOTE: the model only uses some features
# plot of ensemble trees
xgb.plot.multi.trees(model = xgb.fit.final.re, feature_names = names)

# Create box plot of ssc_p per status
ggplot(recruit, aes(x = status, y = ssc_p, fill = status)) +
  geom_boxplot() +
  stat_summary(
    fun = "median",
    geom = "point",
    shape = 18,
    size = 3,
    color = "red",
    position = position_dodge(width = 0.75)
  ) +
  stat_summary(
    fun = "median",
    geom = "text",
    aes(label = paste("Median =", round(..y.., 2))),
    vjust = -1,
    position = position_dodge(width = 0.75)
  ) +
  stat_summary(
    fun = function(x) quantile(x, 0.25),
    geom = "point",
    shape = 18,
    size = 3,
    color = "blue",
    position = position_dodge(width = 0.75)
  ) +
  stat_summary(
    fun = function(x) quantile(x, 0.25),
    geom = "text",
    aes(label = paste("Q1 =", round(..y.., 2))),
    vjust = 1,
    position = position_dodge(width = 0.75)
  ) +
  stat_summary(
    fun = function(x) quantile(x, 0.75),
    geom = "point",
    shape = 18,
    size = 3,
    color = "green",
    position = position_dodge(width = 0.75)
  ) +
  stat_summary(
    fun = function(x) quantile(x, 0.75),
    geom = "text",
    aes(label = paste("Q3 =", round(..y.., 2))),
    vjust = 1,
    position = position_dodge(width = 0.75)
  ) +
  labs(title = "Box Plot of ssc_p by Status",
       x = "Status",
       y = "Secondary Education Percentage (ssc_p)")

# Create box plot of hsc_p per status
ggplot(recruit, aes(x = status, y = hsc_p, fill = status)) +
  geom_boxplot() +
  stat_summary(
    fun = "median",
    geom = "point",
    shape = 18,
    size = 3,
    color = "red",
    position = position_dodge(width = 0.75)
  ) +
  stat_summary(
    fun = "median",
    geom = "text",
    aes(label = paste("Median =", round(..y.., 2))),
    vjust = 1,
    position = position_dodge(width = 0.75)
  ) +
  stat_summary(
    fun = function(x) quantile(x, 0.25),
    geom = "point",
    shape = 18,
    size = 3,
    color = "blue",
    position = position_dodge(width = 0.75)
  ) +
  stat_summary(
    fun = function(x) quantile(x, 0.25),
    geom = "text",
    aes(label = paste("Q1 =", round(..y.., 2))),
    vjust = 1,
    position = position_dodge(width = 0.75)
  ) +
  stat_summary(
    fun = function(x) quantile(x, 0.75),
    geom = "point",
    shape = 18,
    size = 3,
    color = "green",
    position = position_dodge(width = 0.75)
  ) +
  stat_summary(
    fun = function(x) quantile(x, 0.75),
    geom = "text",
    aes(label = paste("Q3 =", round(..y.., 2))),
    vjust = 1,
    position = position_dodge(width = 0.75)
  ) +
  labs(title = "Box Plot of hsc_p by Status",
       x = "Status",
       y = "Higher Secondary Education Percentage (hsc_p)")

# Create box plot of mba_p per status
ggplot(recruit, aes(x = status, y = mba_p, fill = status)) +
  geom_boxplot() +
  stat_summary(
    fun = "median",
    geom = "point",
    shape = 18,
    size = 3,
    color = "red",
    position = position_dodge(width = 0.75)
  ) +
  stat_summary(
    fun = "median",
    geom = "text",
    aes(label = paste("Median =", round(..y.., 2))),
    vjust = -0.5,
    position = position_dodge(width = 0.75)
  ) +
  stat_summary(
    fun = function(x) quantile(x, 0.25),
    geom = "point",
    shape = 18,
    size = 3,
    color = "blue",
    position = position_dodge(width = 0.75)
  ) +
  stat_summary(
    fun = function(x) quantile(x, 0.25),
    geom = "text",
    aes(label = paste("Q1 =", round(..y.., 2))),
    vjust = 1,
    position = position_dodge(width = 0.75)
  ) +
  stat_summary(
    fun = function(x) quantile(x, 0.75),
    geom = "point",
    shape = 18,
    size = 3,
    color = "green",
    position = position_dodge(width = 0.75)
  ) +
  stat_summary(
    fun = function(x) quantile(x, 0.75),
    geom = "text",
    aes(label = paste("Q3 =", round(..y.., 2))),
    vjust = 1,
    position = position_dodge(width = 0.75)
  ) +
  labs(title = "Box Plot of mba_p by Status",
       x = "Status",
       y = "MBA Percentage (mba_p)")
