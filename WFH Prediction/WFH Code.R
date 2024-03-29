knitr::opts_chunk$set(echo = TRUE)

# Import library
library(caret)
library(ggplot2)
library(dplyr)
library(tidyr)
library(smotefamily)
library(rpart.plot)
library(themis)
library(rattle)
library(randomForest)
library(xgboost)
library(fastDummies)
library(devtools)
#devtools::install_url('https://github.com/catboost/catboost/releases/download/v1.2.1/catboost-R-Darwin-1.2.1.tgz', INSTALL_opts = c("--no-multiarch", "--no-test-load", "--no-staged-install"))
library(catboost)
library(partykit)
library(iml)
library(rpart.plot)
library(lime)
library(pROC)

# Import data
wfh <- read.csv("data.csv")

# Rename variables for easy using
colnames(wfh)[3] <- "Have.Children" # Do you have children
colnames(wfh)[7] <- "Work.Exp.in.Category" # Working experience in chosen employment category
colnames(wfh)[8] <- "Commuting.Distance" # How far is it from home to workplace
colnames(wfh)[9] <- "Transpotation" # Mode of transportation
colnames(wfh)[10] <- "Monthly.Salary" # Monthly salary (optional)
colnames(wfh)[11] <- "Online.Work.before19" # Do you have working online experience before pandemic
colnames(wfh)[12] <- "Online.Work.during19" # Do you have working online experience during pandemic
colnames(wfh)[13] <- "Office.Days.during19" # How many days in a week you go to workplace during pandemic
colnames(wfh)[14] <- "Online.Hours" # How much time do you spend working online per day
colnames(wfh)[15] <- "Ease.Completed.Task" # Can you easily complete the assigned duties while working online
colnames(wfh)[16] <- "Work.Life.Balance" # Can you balance your personal like while working online
colnames(wfh)[17] <- "Tech.Supplies" # Do you have better item (laptop,desktop,iphone,etc.) to work online
colnames(wfh)[18] <- "Internet.Access" # Do have better internet access to work online
colnames(wfh)[19] <- "Internet.Coverage" # Internet coverage signal in hometown
colnames(wfh)[20] <- "Data.Charge" # Data Charge bill for online working during pandemic
colnames(wfh)[21] <- "Computer.Skill" # Do you have enough basic skills to operate a computer
colnames(wfh)[22] <- "English.for.Internet" # Do you think your English is enough to handle computer Internet
colnames(wfh)[23] <- "Prefer.OnlineWork.during19" # Do you like online working during pandemic
colnames(wfh)[24] <- "Target"

# Impute missing salary by mode per emloyment category and work experience
# Function to impute missing values with the most frequent category
impute_mode <- function(x) {
  # If there are multiple modes, return the first one
  mode_values <- names(sort(table(x[x!=""]), decreasing = TRUE))
  x[x==''] <- mode_values[1]
}
# Impute missing values by mode within each group
data <- wfh %>%
  group_by(Employment.Category, Work.Exp.in.Category) %>%
  mutate(Monthly.Salary = impute_mode(Monthly.Salary)) %>%
  ungroup()

# Transform categorical variables to factor (ordinal factor for certain variables)
data$Target <- as.factor(data$Target)
data$Age <- factor(data$Age, levels = c("Under 20  years","21 - 30 years",
                                        "31  - 40 years","41 - 50 years",
                                        "Above 51 years"), ordered = TRUE)
data$Work.Exp.in.Category <- factor(data$Work.Exp.in.Category
                                    , levels = c("Under 2 years","2 - 5 years",
                                               "5 - 10 years","Above 10 years")
                                    , ordered = TRUE)
data$Commuting.Distance <- factor(data$Commuting.Distance
                                  , levels = c("Less than 10KM","10KM - 30KM",
                                               "30KM - 50KM","More than 50KM")
                                  , ordered = TRUE)
data$Monthly.Salary <- factor(data$Monthly.Salary
                              , levels = c("RS 0 - 25000","RS 25000 - 50000",
                                           "RS 50000 - 100000","RS 100000 +")
                              , ordered = TRUE)
data$Online.Work.before19 <- factor(data$Online.Work.before19
                                    , levels = c(0,1,2,3,4,5), ordered = TRUE)
data$Online.Work.during19 <- factor(data$Online.Work.during19
                                    , levels = c(0,1,2,3,4,5), ordered = TRUE)
data$Online.Hours <- factor(data$Online.Hours
                            , levels = c("No","Below 5 hours","6 hours - 10 hours"
                                         ,"Above 11 hours"), ordered = TRUE)
data$Ease.Completed.Task <- factor(data$Ease.Completed.Task
                                   , levels = c(1,2,3,4,5), ordered = TRUE)
data$Work.Life.Balance <- factor(data$Work.Life.Balance
                                   , levels = c(1,2,3,4,5), ordered = TRUE)
data$Internet.Coverage <- factor(data$Internet.Coverage
                                 , levels = c(1,2,3,4,5), ordered = TRUE)
data$Data.Charge <- factor(data$Data.Charge
                           , levels = c(1,2,3,4,5), ordered = TRUE)
data$Computer.Skill <- factor(data$Computer.Skill
                              , levels = c(1,2,3,4,5), ordered = TRUE)
data$English.for.Internet <- factor(data$English.for.Internet
                                    , levels = c(1,2,3,4,5), ordered = TRUE)
data$Prefer.OnlineWork.during19 <- factor(data$Prefer.OnlineWork.during19
                                          , levels = c(1,2,3,4,5), ordered = TRUE)
data$Gender <- as.factor(data$Gender)
data$Marital.Status <- as.factor(data$Marital.Status)
data$Have.Children <- as.factor(data$Have.Children)
data$Type.of.working.place <- as.factor(data$Type.of.working.place)
data$Employment.Category <- as.factor(data$Employment.Category)
data$Tech.Supplies <- as.factor(data$Tech.Supplies)
data$Internet.Access <- as.factor(data$Internet.Access)
data$Transpotation <- as.factor(data$Transpotation)

# Check the balance of target variable
prop.table(table(data$Target))

# Create the training and test datasets
set.seed(123)
# Step 1: Get row numbers for the training data
dbRowNumbers <- createDataPartition(data$Target, p=0.7, list=FALSE)
# Step 2: Create the training  dataset
train_data <- data[dbRowNumbers,]
# Step 3: Create the test dataset 
test_data <- data[-dbRowNumbers,]
# Store X and Y for later use.
x_train <- train_data[,-24]
y_train <- train_data$Target

# Train model using logistic regression
start.time1 <- Sys.time() # start time to calculate computation time
logistic_model <- glm(Target ~ ., data = train_data, family = "binomial")
#summary(logistic_model)
end.time1 <- Sys.time() # end time to calculate computation time

# Computation time
run.time1 <- round(end.time1 - start.time1,4)
run.time1

# Predict target variable on testing set
response <- predict(logistic_model, test_data[,-24], type = 'response')
log_result <- ifelse(response>0.5,"Yes","No")
# Confusion matrix to check performance
log_x1 <- table(log_result,test_data$Target)
confusion_matrix_log <- confusionMatrix(log_x1, positive='Yes')
confusion_matrix_log

# Conduct chi-square test for all categorical variables
# Create a list of categorical variable combinations
variables <- data[,-c(13,24)]
variable_combinations <- combn(names(variables), 2, simplify = TRUE)
# Perform chi-square tests for each combination
p_values <- apply(variable_combinations, 2, function(vars) {
  contingency_table <- table(variables[, vars])
  chi_square_test <- chisq.test(contingency_table)
  return(chi_square_test$p.value)
})
# Combine variable names and p-values into a data frame
result_df <- data.frame(
  Variable1 = variable_combinations[1, ],
  Variable2 = variable_combinations[2, ],
  P_Value = round(p_values,6))
# Create a pivot table
pivot_table <- result_df %>%
  pivot_wider(names_from = Variable2, values_from = P_Value)
write.table(pivot_table, file = 'chi_square_results.txt', col.names = TRUE,
             row.names = FALSE, sep = "\t")

# Set up train control
set.seed(123)
cvIndex3 <- createFolds(factor(train_data$Target), 5, returnTrain = T)
train_control3 <- trainControl(method = "cv", index = cvIndex3, number = 5)
# Set up grid search
Grid3 = expand.grid(mtry = seq(1,23,by=1))

# Train model using random forest
start.time2 <- Sys.time() # start time for calculating computation time
set.seed(123)
forest_model <- train(Target ~., data = train_data, method = "rf"
                      , trControl = train_control3, tuneGrid = Grid3)
end.time2 <- Sys.time() # end time for calculating computation time
confusionMatrix(forest_model)
# Plot of tuning hyperparameters
plot(forest_model)

# Computation time
run.time2 <- round(end.time2 - start.time2,4)
run.time2

# Predict target variable on testing set
forest_result <- predict(forest_model, test_data[,-24])
# Confusion matrix to check performance
forest_x1 <- table(forest_result,test_data$Target)
confusion_matrix_fo <- confusionMatrix(forest_x1, positive='Yes')
confusion_matrix_fo

# Copy train_data to new dataframe
cat_train <- train_data 
# Convert ordinal variables back to numeric
cat_train <- mutate_if(cat_train, is.ordered, as.numeric)

# Set up train control
set.seed(123)
cvIndex6 <- createFolds(cat_train$Target, 5, returnTrain = T)
train_control6 <- trainControl(method = "cv", index = cvIndex6, number = 5)
# Set up grid search
Grid6 = expand.grid(depth = c(4,6,8),
                    learning_rate = seq(0.1,0.3,by=0.1),
                    iterations = 1000,
                    l2_leaf_reg = c(0.1,1,10),
                    rsm = seq(0.5,0.9,0.1),
                    border_count = 128)

# Train model using catboost
start.time6 <- Sys.time() # start time for calculating computation time
set.seed(123)
cat_model <- train(cat_train[,-24], cat_train$Target, method = catboost.caret
                   , logging_level = 'Silent'
                   , trControl = train_control6, tuneGrid = Grid6
                   , early_stopping_rounds = 100)
end.time6 <- Sys.time() # end time for calculating computation time
confusionMatrix(cat_model)

# Computation time
run.time6 <- round(end.time6 - start.time6,4)
run.time6

# Copy test_data to new dataframe
cat_test <- test_data 
# Convert ordinal variables back to numerical variables
cat_test <- mutate_if(cat_test, is.ordered, as.numeric)

# Predict target variable on testing set
cat_result <- predict(cat_model, cat_test[,-24])
# Confusion matrix to check performance
cat_x1 <- table(cat_result,cat_test$Target)
confusion_matrix_cat <- confusionMatrix(cat_x1, positive='Yes')
confusion_matrix_cat

#ROC-curve using pROC library
roc_score=roc(as.numeric(cat_test$Target), as.numeric(cat_result))
plot(roc_score ,main ="ROC curve")

# Copy train_data to new dataframe
data_prep <- train_data 
# Convert Target variable to numeric
data_prep$Target <- ifelse(data_prep$Target=="Yes",1,0)
# Convert ordinal variables back to numerical variables
data_prep <- mutate_if(data_prep, is.ordered, as.numeric)
# Convert nominal variables to dummy variables
data_prep <- dummy_cols(data_prep, select_columns = names(data_prep)[sapply(data_prep, is.factor)])
data_prep <- data_prep[,-which(sapply(data_prep, is.factor))]

# Copy to new dataframe for SVM
data_train_svm <- data_prep[, !colnames(data_prep) %in% c("Target")]
# Store mean_train, sd_train for later use
mean_train <- apply(data_train_svm, 2, mean)
sd_train <- apply(data_train_svm, 2, sd)
# Scale predictors of training data
data_train_svm <- data.frame(scale(data_train_svm))
# Get dependent variable
data_train_svm$Target <- as.factor(data_prep$Target)

# Set up train control
set.seed(123)
cvIndex5 <- createFolds(factor(data_train_svm$Target), 5, returnTrain = T)
train_control5 <- trainControl(method = "cv", index = cvIndex5, number = 5)

# Set up grid search
Grid5 = expand.grid(sigma = seq(0.001,1,0.01), C = seq(1,10,1))

# Train model
set.seed(123)
start.time5 <- Sys.time()
svm_ra_model <- train(Target ~., data = data_train_svm
                  , method = "svmRadial", trControl = train_control5, tuneGrid = Grid5)
end.time5 <- Sys.time()
# Results of training model
confusionMatrix(svm_ra_model)

# Computation time
run.time5 <- round(end.time5 - start.time5,4)
run.time5

# Plot of tuning Cost and Sigma vs Accuracy
figure <- plot(svm_ra_model)
figure
# Pre-processing testing data for SVM
# Copy test_data to new dataframe
test_prep <- test_data 
# Convert Target variable to numeric
test_prep$Target <- ifelse(test_prep$Target=="Yes",1,0)
# Convert ordinal variables back to numeric
test_prep <- mutate_if(test_prep, is.ordered, as.numeric)
# Convert nominal variables to dummy variables
test_prep <- dummy_cols(test_prep, select_columns = names(test_prep)[sapply(test_prep, is.factor)])
test_prep <- test_prep[,-which(sapply(test_prep, is.factor))]

# Get variables (X) and target (Y) for test set
x_test_svm <- test_prep[, !colnames(test_prep) %in% c("Target")]
y_test_svm <- test_prep$Target
# Scale testing data using mean_train, sd_train
test_data_scaled <- data.frame(scale(x_test_svm, center = mean_train, scale = sd_train))
# Predict using SVM model
svm_result <- predict(svm_ra_model, test_data_scaled)
# Confusion matrix to assess model performance
svm_x1 <- table(svm_result,y_test_svm)
confusion_matrix_svm <- confusionMatrix(svm_x1, positive = "1")
confusion_matrix_svm

# Combine train data and corresponding prediction from Catboost
new_data <- cat_train[,-24]
new_data$Predicted <- predict(cat_model)
# Train decision tree on new dataset
de_model <- rpart(Predicted ~., data = new_data, method = 'class')
# Evaluate the surrogate model using Accuracy
x <- predict(de_model)
x <- ifelse(x[,1]<=x[,2],"Yes","No")
confusionMatrix(table(x,new_data$Predicted))

# Visualisation of decision tree
rpart.plot(de_model)

# Plot of Variable importace
var <- varImp(de_model)
var$Feature <- rownames(var)
# Sort the dataframe of Variable Importance in descending order
var_desc <- head(var[order(-var$Overall),],10)
# Sort Feature in descending order by Overall Importance
var_desc$Feature <- factor(var_desc$Feature, levels = rev(var_desc$Feature))
# Create horizontal barplot in descending order using ggplot
ggplot(data = var_desc, aes(x = Overall, y = Feature)) + 
  geom_bar(stat = "identity") +
  labs(title = "Variable Importance",
       x = "Importance",
       y = "Variable") +
  theme_minimal()

# Find incorrectly predicted instances
cat_test2 <- cat_test # copy a new dataframe
# Add predicted column to new dataframe
cat_test2$Predicted <- cat_result
# Return row numbers of incorrect predictions
which(cat_test2$Predicted != cat_test2$Target)

# Create an explainer object from training set
explainer <- lime(cat_train, cat_model)
# Generate explanation for 4 observations
set.seed(123)
explanation <- explain(cat_test[c(10,27,43,75), ], explainer, n_features = 10
                       , feature_select = "highest_weights", labels = "Yes"
                       , n_permutations = 5000, kernel_width = 3)

# Visualisation
plot_features(explanation)
