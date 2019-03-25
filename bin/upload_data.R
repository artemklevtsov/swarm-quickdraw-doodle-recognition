#!/usr/bin/env Rscript


## ---- Парсинг аргументов командной строки ----

doc <- '
Usage:
  upload_data.R --help
  upload_data.R [options]

Options:
  -h --help                   Show this message.
  -i --input-file=<file>      Input file [default: ./data/train_simplified.zip].
  -d --db-dir=<path>          Path to database directory [default: ./db].
'
args <- docopt::docopt(doc)


## ---- Константы ----

# Zip-архив
zipfile <- args[["input-file"]]
# Директория с файлами базы данных
db_dir <- Sys.getenv("DBDIR", args[["db-dir"]])


## ---- Проверка аргументов ----

if (!dir.exists(db_dir)) {
  message("Create ", shQuote(db_dir), " directory")
  dir.create(db_dir)
}

checkmate::assert_file_exists(zipfile, access = "r", extension = "zip", .var.name = "input-file")
checkmate::assert_directory_exists(db_dir, access = "w", .var.name = "db-dir")


## ---- Подключение к базе данных ----

message("Connect to database")
con <- DBI::dbConnect(drv = MonetDBLite::MonetDBLite(), db_dir)


## ---- Отключение от базы данных ----

# Выполняеися перед заверешнием сессии (в том числе в случае возникновения ошибки)
invisible(reg.finalizer(
  e = .GlobalEnv,
  f = function(e) {
    message("Disconnect from database")
    DBI::dbDisconnect(con, shutdown = TRUE)
  },
  onexit = TRUE
))

# Включить для отладки
options(monetdb.debug.query = FALSE)

# message("Remove all tables from database")
# for (tbl in dbListTables(con)) dbRemoveTable(con, tbl)

if (!DBI::dbExistsTable(con, "upload_log")) {
  message("Create 'upload_log' table")
  DBI::dbCreateTable(
    con = con,
    name = "upload_log",
    fields = c(
      "id" = "serial",
      "file_name" = "text UNIQUE",
      "uploaded" = "bool DEFAULT false"
    )
  )
}

if (!DBI::dbExistsTable(con, "doodles")) {
  message("Create 'doodles' table")
  DBI::dbCreateTable(
    con = con,
    name = "doodles",
    fields = c(
      "countrycode" = "char(2)",
      "drawing" = "text",
      "key_id" = "bigint",
      "recognized" = "bool",
      "timestamp" = "timestamp",
      "word" = "text"
    )
  )
}


## ---- Функции для работы с ФС и БД ----

# Извлечение и загрузка файла
upload_file <- function(con, tablename, zipfile, filename) {
  checkmate::assert_class(con, "MonetDBEmbeddedConnection")
  checkmate::assert_string(tablename)
  checkmate::assert_string(filename)
  checkmate::assert_true(DBI::dbExistsTable(con, tablename))
  checkmate::assert_file_exists(zipfile, access = "r", extension = "zip")

  path <- file.path(tempdir(), filename)
  unzip(zipfile, files = filename, exdir = tempdir(), junkpaths = TRUE, unzip = getOption("unzip"))
  on.exit(unlink(file.path(path)))
  sql <- sprintf("COPY OFFSET 2 INTO %s FROM '%s' USING DELIMITERS ',','\\n','\"' NULL AS '' BEST EFFORT", tablename, path)
  DBI::dbExecute(con, sql)
  DBI::dbExecute(con, sprintf("INSERT INTO upload_log(file_name, uploaded) VALUES('%s', true)", filename))
  invisible(TRUE)
}


## ---- Выгрузка данных ----

files <- unzip(zipfile, list = TRUE)$Name
to_skip <- DBI::dbGetQuery(con, "SELECT file_name FROM upload_log")[[1L]]
files <- setdiff(files, to_skip)

if (length(files) == 0L) {
  message("No files to upload")
  message("Disconnect from database")
  DBI::dbDisconnect(con, shutdown = TRUE)
  quit(save = "no", status = 0L)
}

message("Upload files to database")
pb <- txtProgressBar(min = 0L, max = length(files), style = 3)
for (i in seq_along(files)) {
  upload_file(con = con, tablename = "doodles", zipfile = zipfile, filename = files[i])
  setTxtProgressBar(pb, i)
}
close(pb)


## ---- Добавление столбцов ----

message("Generate lables")
invisible(DBI::dbExecute(con, "ALTER TABLE doodles ADD label_int int"))
invisible(DBI::dbExecute(con, "UPDATE doodles SET label_int = dense_rank() OVER (ORDER BY word) - 1"))


## ---- Создание индексов ----

message("Generate row numbers")
invisible(DBI::dbExecute(con, "ALTER TABLE doodles ADD id serial"))
invisible(DBI::dbExecute(con, "CREATE ORDERED INDEX doodles_id_ord_idx ON doodles(id)"))
