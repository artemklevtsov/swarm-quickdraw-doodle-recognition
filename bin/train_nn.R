#!/usr/bin/env Rscript

## ---- Парсинг аргументов командной строки ----

doc <- '
Usage:
  train_nn.R --help
  train_nn.R --list-models
  train_nn.R [options]

Options:
  -h --help                   Show this message.
  -l --list-models            List available models.
  -m --model=<model>          Neural network model name [default: mobilenet_v2].
  -b --batch-size=<size>      Batch size [default: 32].
  -s --scale-factor=<ratio>   Scale factor [default: 0.5].
  -c --color                  Use color lines [default: FALSE].
  -d --db-dir=<path>          Path to database directory [default: Sys.getenv("db_dir")].
  -r --validate-ratio=<ratio> Validate sample ratio [default: 0.995].
  -n --n-gpu=<number>         Number of GPUs [default: 1].
'
args <- docopt::docopt(doc)

# Раскомментировать при запуске с использованием окружения conda
# reticulate::use_condaenv("r-tensorflow")

if (args[["help"]]) {
  cat(doc, file = stdout())
  quit(save = "no", status = 0L)
}

if (isTRUE(args[["list-models"]])) {
  # avail_nn_models <- ls(envir = asNamespace("keras"), pattern = "^application_")
  # avail_nn_models <- gsub("application_", "", avail_nn_models, fixed = TRUE)
  doc <- help.search("application_", package = "keras")
  print.data.frame(doc$matches[, c("Entry", "Title")], row.names = FALSE)
  quit(save = "no", status = 0L)
}


## ---- Константы ----

# Директория с БД
db_dir <- args[["db-dir"]]
if (db_dir == 'Sys.getenv("db_dir")') {
  db_dir <- Sys.getenv("db_dir")
}
# название модели
model_name <- args[["model"]]
# размер батча
batch_size <- as.integer(args[["batch-size"]])
# коэффициент ресайза изображений
scale_factor <- as.double(args[["scale-factor"]])
# Использование цвета
color <- isTRUE(args[["color"]])
# Количество каналов изображения
channels <- if (color) 3L else 1L
# Соотношение выборки валидации
validate_ratio <- as.double(args[["validate-ratio"]])
# Количество GPU
n_gpu <- as.integer(args[["n-gpu"]])


## ---- Проверка аргументов ----

if (!dir.exists("models")) {
  message("Create 'models' directory")
  dir.create("models")
}

if (!dir.exists("logs")) {
  message("Create 'logs' directory")
  dir.create("logs")
}

checkmate::assert_directory_exists(db_dir, access = "w", .var.name = "db-dir")
checkmate::assert_choice(model_name, gsub("application_", "", ls(envir = asNamespace("keras"), pattern = "^application_")), .var.name = "model")
checkmate::assert_count(batch_size, na.ok = FALSE, .var.name = "batch")
checkmate::assert_number(scale_factor, lower = 0.01, upper = 5, na.ok = FALSE, finite = TRUE, .var.name = "scale-factor")
checkmate::assert_flag(color, na.ok = FALSE, .var.name = "color")


## ---- Информация о параметрах запуска ----

message("Use DB: ", shQuote(db_dir))
message("Use model: ", model_name)
message("Use color: ", color)
message("Use scale factor: ", signif(scale_factor, 2))
message("Use batch size: ", batch_size)
message("Use validation ratio: ", signif(validate_ratio, 3))


## ---- Компиляция C++ функций ----

message("Compile C++ code")
source("utils/rcpp.R")
Rcpp::sourceCpp("src/cv_xt.cpp")


## ---- Подключение к базе данных ----

message("Connect to database")
con <- DBI::dbConnect(drv = MonetDBLite::MonetDBLite(), db_dir)


## --- Импорт скриптов ----

source("utils/keras_iterator.R")
source("utils/get_model.R")


## ---- Итераторы ----

message("Prepare iterators")

# общее число наблюдений
n <- DBI::dbGetQuery(con, "SELECT count(*) FROM doodles")[[1L]]
# Размер стороны картинки
dim_size <- scale_factor * 256
# Размер входного слоя сети
input_shape <- c(dim_size, dim_size, 3)
# количество классов целевой переменной
num_classes <- DBI::dbGetQuery(con, "SELECT count(DISTINCT label_int) FROM doodles")[[1L]]
ind <- seq_len(n)
set.seed(42)
train_ind <- sample(ind, floor(length(ind) * validate_ratio))
val_ind <- ind[-train_ind]
reserved_ind <- val_ind[1:200000] # 200k наблюдений для модели 2 уровня
val_ind <- val_ind[-c(1:200000)]
rm(ind)

train_iterator <- train_generator(
  db_connection = con,
  samples_index = train_ind,
  num_classes = num_classes,
  batch_size = batch_size,
  scale = scale_factor,
  color = color,
  imagenet_preproc = TRUE
)

val_iterator <- train_generator(
  db_connection = con,
  samples_index = val_ind,
  num_classes = num_classes,
  batch_size = batch_size,
  scale = scale_factor,
  color = color,
  imagenet_preproc = TRUE
)


## ---- Модель ----

message("Prepare model")

keras::k_clear_session()

top_3_categorical_accuracy <- keras::custom_metric(
  name = "top_3_categorical_accuracy",
  metric_fn = function(y_true, y_pred) {
    keras::metric_top_k_categorical_accuracy(y_true, y_pred, k = 3)
  }
)

weights <- if (color) "imagenet" else NULL

if (n_gpu > 1L) {
  # Модель загружется на CPU без компиляции
  with(tensorflow::tf$device("/cpu:0"), {
    model_cpu <- get_model(
      name = model_name,
      input_shape = input_shape,
      weights = weights,
      metrics = c(top_3_categorical_accuracy),
      color = color,
      compile = FALSE
    )
  })
  # Передается нескомпилированная модель
  model <- keras::multi_gpu_model(model_cpu, gpus = n_gpu)
  keras::compile(
    object = model,
    optimizer = keras::optimizer_adam(lr = 0.0004),
    loss = "categorical_crossentropy",
    metrics = c(top_3_categorical_accuracy)
  )
} else {
  model <- get_model(
    name = model_name,
    input_shape = input_shape,
    num_classes = num_classes,
    optimizer = keras::optimizer_adam(lr = 0.002),
    weights = weights,
    metrics = c(top_3_categorical_accuracy),
    color = color,
    compile = !color
  )

  if (color) {
    # Предобучение последнего слоя с запорозкой остальных слоев
    keras::freeze_weights(model, to = "global_average_pooling2d_1")
    keras::compile(
      object = model,
      optimizer = keras::optimizer_adam(lr = 0.001),
      loss = "categorical_crossentropy",
      metrics = c(top_3_categorical_accuracy)
    )
    keras::fit_generator(
      object = model,
      generator = train_iterator,
      steps_per_epoch = 200,
      epochs = 3,
      verbose = 2,
      validation_data = val_iterator,
      validation_steps = 50,
      callbacks = NULL
    )
    keras::unfreeze_weights(model, to = "global_average_pooling2d_1")
    keras::compile(
      object = model,
      optimizer = keras::optimizer_adam(lr = 0.0004),
      loss = "categorical_crossentropy",
      metrics = c(top_3_categorical_accuracy)
    )
  }
}

## ---- Колбеки ----

# Шаблон имени файла лога
message("Create callbacks list")
log_file_tmpl <- file.path("logs", sprintf(
  "%s_%d_%dch_%s.csv",
  model_name,
  dim_size,
  channels,
  format(Sys.time(), "%Y%m%d%H%M%OS")
))
# Шаблон имени файла модели
model_file_tmpl <- file.path("models", sprintf(
  "%s_%d_%dch_{epoch:02d}_{val_loss:.2f}.h5",
  model_name,
  dim_size,
  channels
))

callbacks_list <- list(
  keras::callback_csv_logger(
    filename = log_file_tmpl
  ),
  keras::callback_early_stopping(
    monitor = "val_loss",
    min_delta = 1e-4,
    patience = 8,
    verbose = 1,
    mode = "min"
  ),
  keras::callback_reduce_lr_on_plateau(
    monitor = "val_loss",
    factor = 0.5, # уменьшаем lr в 2 раза
    patience = 4,
    verbose = 1,
    min_delta = 1e-4,
    mode = "min"
  ),
  keras::callback_model_checkpoint(
    filepath = model_file_tmpl,
    monitor = "val_loss",
    save_best_only = FALSE,
    save_weights_only = FALSE,
    mode = "min"
  )
)


## ---- Обучение модели ----

message("Fit model")
keras::fit_generator(
  object = model,
  generator = train_iterator,
  steps_per_epoch = 200,
  epochs = 100,
  verbose = 2,
  validation_data = val_iterator,
  validation_steps = 80,
  callbacks = callbacks_list
)


## ---- Отключение от базы данных ----

message("Disconnect from database")
DBI::dbDisconnect(con, shutdown = TRUE)
