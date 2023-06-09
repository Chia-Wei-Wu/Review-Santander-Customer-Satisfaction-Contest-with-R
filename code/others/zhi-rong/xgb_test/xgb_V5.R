# * add cross validation
# Private: 0.8243
# Public: 0.83772

library(tidyverse)
library(xgboost)
library(caret)
library(ROCR)
library(ParBayesianOptimization)

set.seed(123)

train <- read.csv("./data/Input/train.csv")
test  <- read.csv("./data/Input/test.csv")


##### Removing IDs
train$ID <- NULL
test.id <- test$ID
test$ID <- NULL

##### Extracting TARGET
train.y <- train$TARGET
train$TARGET <- NULL

##### 0 count per line
count0 <- function(x) {
    return(sum(x == 0))
}
train$n0 <- apply(train, 1, FUN = count0)
test$n0 <- apply(test, 1, FUN = count0)

##### Removing constant features
cat("\n## Removing the constants features.\n")
for (f in names(train)) {
    if (length(unique(train[[f]])) == 1) {
        # cat(f, "is constant in train. We delete it.\n")
        train[[f]] <- NULL
        test[[f]] <- NULL
    }
}

##### Removing identical features
features_pair <- combn(names(train), 2, simplify = F)
toRemove <- c()
for (pair in features_pair) {
    f1 <- pair[1]
    f2 <- pair[2]
    
    if (!(f1 %in% toRemove) & !(f2 %in% toRemove)) {
        if (all(train[[f1]] == train[[f2]])) {
            # cat(f1, "and", f2, "are equals.\n")
            toRemove <- c(toRemove, f2)
        }
    }
}

feature.names <- setdiff(names(train), toRemove)

train <- train[, feature.names]
test <- test[, feature.names]


# Create additional features
# var38mc == 1 when var38 has the most common value and 0 otherwise
# logvar38 is log transformed feature when var38mc is 0, zero otherwise

train <- train %>%
    # This column mark the most common value
    mutate(var38mc = ifelse(near(var38, 117310.979016494), 1, 0), ) %>%
    
    # This column will be normal distributed
    mutate (logvar38 = ifelse(var38mc == 0, log(var38), 0))

test <- test %>%
    # This column mark the most common value
    mutate(var38mc = ifelse(near(var38, 117310.979016494), 1, 0), ) %>%
    
    # This column will be normal distributed
    mutate (logvar38 = ifelse(var38mc == 0, log(var38), 0))


# add log_saldo_var30
train$log_saldo_var30 <- train$saldo_var30

smallest_positive_value <-
    min(train$log_saldo_var30[train$log_saldo_var30 > 0], na.rm = TRUE)

# remove negitive values
train$log_saldo_var30[train$log_saldo_var30 < smallest_positive_value] <-
    smallest_positive_value

train <- train %>%
    mutate(log_saldo_var30 = ifelse(
        log_saldo_var30 > smallest_positive_value,
        log(log_saldo_var30),
        0
    ))


test$log_saldo_var30 <- test$saldo_var30

smallest_positive_value <-
    min(test$log_saldo_var30[test$log_saldo_var30 > 0], na.rm = TRUE)

# remove negitive values
test$log_saldo_var30[test$log_saldo_var30 < smallest_positive_value] <-
    smallest_positive_value

test <- test %>%
    mutate(log_saldo_var30 = ifelse(
        log_saldo_var30 > smallest_positive_value,
        log(log_saldo_var30),
        0
    ))

##### limit vars in test based on min and max vals of train (Remove Outlier)
print('Setting min-max lims on test data')
for (f in colnames(train)) {
    lim <- min(train[, f])
    test[test[, f] < lim, f] <- lim
    
    lim <- max(train[, f])
    test[test[, f] > lim, f] <- lim
}

##### Model Tuning
dtrain <- xgb.DMatrix(data = as.matrix(train), label = as.numeric(train.y))
dtest <- xgb.DMatrix(data = as.matrix(test))

params <- list(
    max_depth = 5,
    eta = 0.05,
    gamma = 0.01,
    min_child_weight = 0,
    subsample = 0.5,
    colsample_bytree=0.75,
    booster = "gbtree",
    objective = "binary:logistic",
    eval_metric = "auc",
    verbosity = 0
)

# xgboost 內建的 Cross Validation
xgbCV <- xgb.cv(
    params = params,
    data = dtrain,
    nrounds = 100,
    prediction = TRUE,
    showsd = TRUE,
    early_stopping_rounds = 10,
    maximize = TRUE,
    nfold = 10,
    stratified = TRUE
)

cat(xgbCV$best_iteration)

# 訓練模型
model <- xgb.train(
    params = params,
    data = dtrain,
    nrounds = xgbCV$best_iteration
)

preds <- predict(model, dtest)

# 可以印出哪些 features 對 xgboost 是重要的，取前 20 名
mat <- xgb.importance (feature_names = colnames(train), model = model)
xgb.plot.importance (importance_matrix = mat[1:20])


# 預測
predict_df <- data.frame(ID = test.id, TARGET = preds)

write.csv(
    predict_df,
    file = './data/Output/submission_xgb_V5.csv',
    quote = FALSE,
    row.names = FALSE
)