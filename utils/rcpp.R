## ---- Rcpp плагины ----

# OpenCV функции
Rcpp::registerPlugin("opencv", function() {
  # Возможные названия пакета
  pkg_config_name <- c("opencv", "opencv4")
  # Бинарный файл утилиты pkg-config
  pkg_config_bin <- Sys.which("pkg-config")
  # Проврека наличия утилиты в системе
  checkmate::assert_file_exists(pkg_config_bin, access = "x")
  # Проверка наличия файла настроек OpenCV для pkg-config
  check <- sapply(pkg_config_name, function(pkg) system(paste(pkg_config_bin, pkg)))
  if (all(check != 0)) {
    stop("OpenCV config for the pkg-config not found", call. = FALSE)
  }

  pkg_config_name <- pkg_config_name[check == 0]
  list(env = list(
    PKG_CXXFLAGS = system(paste(pkg_config_bin, "--cflags", pkg_config_name), intern = TRUE),
    PKG_LIBS = system(paste(pkg_config_bin, "--libs", pkg_config_name), intern = TRUE)
  ))
})
