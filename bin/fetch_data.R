#!/usr/bin/env Rscript


## ---- Парсинг аргументов командной строки ----

doc <- '
Usage:
  fetch_data.R --help
  fetch_data.R [options]

Options:
  -h --help                   Show this message.
  -c --credentials=<file>     Path to config file [default: ~/.kaggle/kaggle.json].
  -o --output-dir=<path>      Path to output directory [default: ./data].
  -w --overwrite              Overwrite existing files [default: FALSE].
'
args <- docopt::docopt(doc)


## ---- Константы ----

# Перезаписывать существующие файлы
overwrite <- isTRUE(args[["overwrite"]])
# Файл с ключом доступа к API
kaggle_conf_file <- args[["credentials"]]
# Директория для скачивания фпйлов
out_dir <- args[["output-dir"]]
# URL для запросов
base_url <- "https://www.kaggle.com/api/v1"
# Путь к соревнованию
slug <- "quickdraw-doodle-recognition"
# Точка доступа к информации о файлах данных
data_list_path <- "competitions/data/list"
# Точка доступа к скачивания файлов данных
data_dl_path <- "competitions/data/download"
# Чтение переменных окружения с данными авторизации
env_creds <- Sys.getenv(c("KAGGLE_USERNAME", "KAGGLE_KEY"))


## ---- Проверка аргументов ----

if (!dir.exists(out_dir)) {
  message("Create ", shQuote(out_dir), " directory")
  dir.create(out_dir)
}

if (is.null(kaggle_conf_file) || !file.exists(kaggle_conf_file)) {
  kaggle_conf_dir <- Sys.getenv("KAGGLE_CONFIG_DIR", path.expand("~/.kaggle"))
  kaggle_conf_file <- file.path(kaggle_conf_dir, "kaggle.json")
}

checkmate::assert_file_exists(kaggle_conf_file, access = "r", extension = "json", .var.name = "credentials")
checkmate::assert_path_for_output(out_dir, overwrite = TRUE, .var.name = "output-dir")


## ---- Получение ключей доступа к API ----

if (all(nzchar(env_creds))) {
  message("Read Kaggle API credentials from environment variables")
  kaggle_user <- Sys.getenv("KAGGLE_USERNAME")
  kaggle_key <- Sys.getenv("KAGGLE_KEY")
} else if (file.exists(kaggle_conf_file)) {
  message("Read Kaggle API credentials from ", shQuote(kaggle_conf_file))
  kaggle_creds <- jsonlite::fromJSON(kaggle_conf_file)
  checkmate::assert_list(kaggle_creds, .var.name = "credentials")
  checkmate::assert_names(names(kaggle_creds), must.include = c("username", "key"), .var.name = "credentials")
  kaggle_user <- kaggle_creds$username
  kaggle_key <- kaggle_creds$key
} else {
  stop("Credentials file ", shQuote(kaggle_conf_file), " does not exists.", call. = FALSE)
}
message("Using @", kaggle_user, " Kaggle profile")


## ---- Получение информации о файлах данных ----

message("Fetch competition files information")
h <- curl::new_handle(
  proxy = Sys.getenv("KAGGLE_PROXY"),
  httpauth = 1L,
  userpwd = paste(kaggle_user, kaggle_key, sep = ":")
)
resp <- curl::curl_fetch_memory(url = paste(base_url, data_list_path, slug, sep = "/"), handle = h)
txt <- rawToChar(resp$content)
res <- jsonlite::fromJSON(txt)


## ---- Загрузка файлов ----

dl_files <- res$ref
dl_files <- c("train_simplified.zip", "test_simplified.csv", "sample_submission.csv")
out_files <- file.path(out_dir, dl_files)
to_skip <- file.exists(out_files)
if (!overwrite && any(to_skip)) {
  message("Skip existing files: ", paste(shQuote(dl_files[to_skip]), collapse = ", "))
  dl_files <- dl_files[!to_skip]
  out_files <- dl_files[!to_skip]
}

if (length(dl_files) == 0L) {
  message("No files to download")
  quit(save = "no", status = 0L)
}

urls <- paste(base_url, data_dl_path, slug, dl_files, sep = "/")

for (i in seq_along(dl_files)) {
  message("Download ", shQuote(basename(out_files[i])))
  res <- curl::curl_download(
    url = urls[i],
    destfile = out_files[i],
    quiet = FALSE,
    handle = h
  )
}
