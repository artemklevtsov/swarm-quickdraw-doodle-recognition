#!/usr/bin/env Rscript


## ---- Парсинг аргументов командной строки ----

doc <- '
Usage:
  json_to_image.R --help
  json_to_image.R [options]

Options:
  -h --help                   Show this message.
  -i --input-file=<file>      Input file [default: ./data/train_simplified.zip].
  -o --output-dir=<dir>        Output directory [default: ./data/images].
  -m --mapping-file=<file>    Mapping file [default: ./data/maping_images.csv]
  -s --scale-factor=<ratio>   Scale factor [default: 1.0].
  -c --color                  Use color lines [default: FALSE].
  -f --image-format=<format>   Image file format [default: PNG].
'
args <- docopt::docopt(doc)

if (args[["help"]]) {
  cat(doc, file = stdout())
  quit(save = "no", status = 0L)
}


## ---- Константы ----

# коэффициент ресайза изображений
scale_factor <- as.double(args[["scale-factor"]])
# Использование цвета
color <- isTRUE(args[["color"]])
# Zip-архив
zipfile <- args[["input-file"]]
# Директория для изображений
out_dir <- args[["output-dir"]]
# Файл для мэппинга изобаржения
mapping_file <- args[["mapping-file"]]
# Расширения файлов изображений
image_fmt <- args[["image-format"]]
image_ext <- paste0(".", tolower(image_fmt))


## ---- Проверка аргументов ----

if (!dir.exists(out_dir)) {
  message("Create ", shQuote(out_dir), " directory")
  dir.create(out_dir)
}

checkmate::assert_directory_exists(out_dir, access = "w", .var.name = "output-dir")
checkmate::assert_file_exists(zipfile, access = "r", extension = "zip", .var.name = "input-file")
checkmate::assert_path_for_output(mapping_file, overwrite = TRUE, .var.name = "mapping-file")
checkmate::assert_number(scale_factor, lower = 0.01, upper = 5, na.ok = FALSE, finite = TRUE, .var.name = "scale-factor")
checkmate::assert_flag(color, na.ok = FALSE, .var.name = "color")
checkmate::assert_choice(toupper(image_fmt), c("PNG", "JPEG", "BMP", "PXM", "TIFF", "WEBP"), .var.name = "image-format")


## ---- Компиляция C++ функций ----

message("Compile C++ code")
# OpenCV функции
Rcpp::registerPlugin("opencv", function() {
  pkg_config_name <- "opencv"
  pkg_config_bin <- Sys.which("pkg-config")
  checkmate::assert_file_exists(pkg_config_bin, access = "x")
  list(env = list(
    PKG_CXXFLAGS = system(paste(pkg_config_bin, "--cflags", pkg_config_name), intern = TRUE),
    PKG_LIBS = system(paste(pkg_config_bin, "--libs", pkg_config_name), intern = TRUE)
  ))
})
Rcpp::sourceCpp("src/cv.cpp")


## ---- Выгрузка данных ----

process <- function(filename) {
  path <- file.path(tempdir(), filename)
  on.exit(unlink(file.path(path)))
  unzip(zipfile, files = filename, exdir = tempdir(), junkpaths = TRUE, unzip = getOption("unzip"))
  data <- data.table::fread(file = path, sep = ",", header = TRUE, select = c("key_id", "drawing", "word"), integer64 = "character")
  data[, filename := file.path(out_dir, paste0(key_id, image_ext))]
  data[, json_vec_save(drawing, filename, scale_factor, color)]
  data[, drawing := NULL]
  data.table::fwrite(x = data, file = mapping_file, append = TRUE, sep = ",", eol = "\n")
}

message("Process images")
files <- unzip(zipfile, list = TRUE)$Name
pb <- txtProgressBar(min = 0L, max = length(files), style = 3)
for (i in seq_along(files)) {
  process(files[i])
  setTxtProgressBar(pb, i)
}
close(pb)
