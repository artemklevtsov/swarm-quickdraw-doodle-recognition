#!/usr/bin/env Rscript

## ---- Парсинг аргументов командной строки ----

doc <- '
Usage:
  train_nn.R --help
  train_nn.R --list-models
  train_nn.R [options]

Options:
  -h --help                   Show this message.
  -m --model=<model>          Neural network model file
  -o --output-dir=<path>      Path to output directory [default: ./data].
  -b --batch-size=<size>      Batch size [default: 32].
  -s --scale-factor=<ratio>   Scale factor [default: 0.5].
  -c --color                  Use color lines [default: FALSE].
  -d --db-dir=<path>          Path to database directory [default: Sys.getenv("db_dir")].
'
args <- docopt::docopt(doc)

# Раскомментировать при запуске с использованием окружения conda
# reticulate::use_condaenv("r-tensorflow")

if (args[["help"]]) {
  cat(doc, file = stdout())
  quit(save = "no", status = 0L)
}


## ---- Параметры ----

# Директория с БД
db_dir <- args[["db-dir"]]
if (db_dir == 'Sys.getenv("db_dir")') {
  db_dir <- Sys.getenv("db_dir")
}
# название модели
model_file <- args[["model"]]
# Директория для скачивания фпйлов
out_dir <- args[["output-dir"]]
# размер батча
batch_size <- as.integer(args[["batch-size"]])
# коэффициент ресайза изображений
scale_factor <- as.double(args[["scale-factor"]])
# Использование цвета
color <- isTRUE(args[["color"]])


## ---- Проверка аргументов ----

checkmate::assert_directory_exists(db_dir, access = "w", .var.name = "db-dir")
checkmate::assert_file_exists(model_file, access = "r", extension = "h5", .var.name = "model-file")
checkmate::assert_path_for_output(out_dir, overwrite = TRUE, .var.name = "output-dir")
checkmate::assert_count(batch_size, na.ok = FALSE, .var.name = "batch")
checkmate::assert_number(scale_factor, lower = 0.01, upper = 5, na.ok = FALSE, finite = TRUE, .var.name = "scale-factor")
checkmate::assert_flag(color, na.ok = FALSE, .var.name = "color")


## ---- Загрузка пакетов ----

suppressMessages(library(data.table))

## ---- Компиляция C++ функций ----

message("Compile C++ code")
source("utils/rcpp.R")
Rcpp::sourceCpp("src/cv_xt.cpp")


## ---- Подключение к базе данных ----

message("Connect to database")
con <- DBI::dbConnect(drv = MonetDBLite::MonetDBLite(), db_dir)


## --- Импорт скриптов ----

source("utils/keras_iterator_test.R")


## ---- Итераторы ----

message("Prepare iterators")

# Тестовые данные
test <- data.table::fread("data/test_simplified.csv", integer64 = "character")

# Итератор по тестовым данным
test_iterator <- test_generator(
  dt = test,
  batch_size = batch_size,
  scale = scale_factor,
  color = color,
  imagenet_preproc = TRUE
)

## ---- Предсказания ----

# Загрузка модели
top_3_categorical_accuracy <- keras::custom_metric(
  name = "top_3_categorical_accuracy",
  metric_fn = function(y_true, y_pred) {
    keras::metric_top_k_categorical_accuracy(y_true, y_pred, k = 3)
  }
)

message("Load model")
model <- keras::load_model_hdf5(
  filepath = model_file,
  custom_objects = c("top_3_categorical_accuracy" = top_3_categorical_accuracy)
)

message("Predict")
# Предсказание классов
pred <- keras::predict_generator(
  object = model,
  generator = test_iterator,
  steps = ceiling(test[, .N] / batch_size),
  verbose = 0
)

message("Prepare submit file")
# Метки классов и слова
dt <- DBI::dbGetQuery(con, "SELECT DISTINCT label_int, word FROM doodles ORDER BY label_int")
data.table::setDT(dt)
dt[, word := gsub(" ", "_", word, fixed = TRUE)]

colnames(pred) <- dt[, as.character(word)]
rownames(pred) <- test[, as.character(key_id)]
pred <- data.table::data.table(pred, keep.rownames = "key_id")

pred <- data.table::melt(pred, id.vars = c("key_id"))
data.table::setorderv(pred, c("key_id", "value"), order = c(1, -1))

pred <- pred[, .(word = paste(variable[1:3], collapse = " ")), by = key_id]

out_file <- file.path(out_dir, gsub(".h5", ".csv", basename(model_file), fixed = TRUE))
zip_file <- paste0(out_file, ".zip")

message("Write ", shQuote(basename(out_file)))
data.table::fwrite(
  x = pred[, .(key_id, word)],
  file = out_file,
  sep = ","
)

message("Compress ", shQuote(basename(out_file)))
zip(zip_file, out_file, flags = "-jq")
unlink(out_file)

## ---- Отключение от базы данных ----

DBI::dbDisconnect(con, shutdown = TRUE)
