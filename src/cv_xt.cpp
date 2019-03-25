// [[Rcpp::plugins(cpp14)]]
// [[Rcpp::plugins(opencv)]]
// [[Rcpp::depends(xtensor)]]
// [[Rcpp::depends(RcppThread)]]

#include <xtensor/xjson.hpp>
#include <xtensor/xadapt.hpp>
#include <xtensor/xview.hpp>
#include <xtensor-r/rtensor.hpp>
#include <opencv2/core/core.hpp>
#include <opencv2/highgui/highgui.hpp>
#include <opencv2/imgproc/imgproc.hpp>
#include <Rcpp.h>
#include <RcppThread.h>

// Синонимы для типов
using RcppThread::parallelFor;
using json = nlohmann::json;
using points = xt::xtensor<double,2>; // Изввчённые из JSON координаты точек
using strokes = std::vector<points>; // Изввчённые из JSON координаты точек
using xtensor3d = xt::xtensor<double, 3>; // Тензор для хранения матрицы изоображения
using xtensor4d = xt::xtensor<double, 4>; // Тензор для хранения множества изображений
using rtensor3d = xt::rtensor<double, 3>; // Обёртка для экспорта в R
using rtensor4d = xt::rtensor<double, 4>; // Обёртка для экспорта в R

// Статические константы
// Размер изображения в пикселях
const static int SIZE = 256;
// Тип линии
// См. https://en.wikipedia.org/wiki/Pixel_connectivity#2-dimensional
const static int LINE_TYPE = cv::LINE_4;
// Толщина линии в пикселях
const static int LINE_WIDTH = 3;
// Алгоритм ресайза
// https://docs.opencv.org/3.1.0/da/d54/group__imgproc__transform.html#ga5bb5a1fea74ea38e1a5445ca803ff121
const static int RESIZE_TYPE = cv::INTER_LINEAR;


// Шаблон для конвертирования OpenCV-матрицы в тензор
template <typename T, int NCH, typename XT=xt::xtensor<T,3,xt::layout_type::column_major>>
XT to_xt(const cv::Mat_<cv::Vec<T, NCH>>& src) {
    std::vector<int> shape = {src.rows, src.cols, NCH};
    size_t size = src.total() * NCH;
    XT res = xt::adapt((T*) src.data, size, xt::no_ownership(), shape);
    return res;
}

// Преобразование JSON в список координат точек
strokes parse_json(const std::string& x) {
    auto j = json::parse(x);
    if (!j.is_array()) {
        throw std::runtime_error("'x' must be JSON array.");
    }
    strokes res;
    res.reserve(j.size());
    for (const auto& a: j) {
        if (!a.is_array() || a.size() != 2) {
            throw std::runtime_error("'x' must include only 2d arrays.");
        }
        auto p = a.get<points>();
        res.push_back(p);
    }
    return res;
}

// Отрисовка линий
// Цвета HSV
cv::Mat ocv_draw_lines(const strokes& x, bool color = true) {
    auto stype = color ? CV_8UC3 : CV_8UC1;
    auto dtype = color ? CV_32FC3 : CV_32FC1;
    auto bg = color ? cv::Scalar(0, 0, 255) : cv::Scalar(255);
    auto col = color ? cv::Scalar(0, 255, 220) : cv::Scalar(0);
    cv::Mat img = cv::Mat(SIZE, SIZE, stype, bg);
    size_t n = x.size();
    for (const auto& s: x) {
        // Количество точек
        size_t n_points = s.shape()[1];
        for (size_t i = 0; i < n_points - 1; ++i) {
            cv::Point from(s(0, i), s(1, i));
            cv::Point to(s(0, i + 1), s(1, i + 1));
            cv::line(img, from, to, col, LINE_WIDTH, LINE_TYPE);
        }
        if (color) {
            // Меняем цвет линии
            col[0] += 180 / n;
        }
    }
    if (color) {
        // Менеяем цветовое представление на RGB
        cv::cvtColor(img, img, cv::COLOR_HSV2RGB);
    }
    // Меняем формат представления на float32 с диапазоном [0, 1]
    img.convertTo(img, dtype, 1 / 255.0);
    return img;
}

// Обработка JSON и получение тензора с данными изоражения
xtensor3d process(const std::string& x, double scale = 1.0, bool color = true) {
    auto p = parse_json(x);
    auto img = ocv_draw_lines(p, color);
    if (scale != 1) {
        cv::Mat out;
        cv::resize(img, out, cv::Size(), scale, scale, RESIZE_TYPE);
        cv::swap(img, out);
        out.release();
    }
    xtensor3d arr = color ? to_xt<double,3>(img) : to_xt<double,1>(img);
    return arr;
}

// [[Rcpp::export]]
rtensor3d cpp_process_json_str(const std::string& x,
                               double scale = 1.0,
                               bool color = true) {
    xtensor3d res = process(x, scale, color);
    return res;
}

// [[Rcpp::export]]
rtensor4d cpp_process_json_vector(const std::vector<std::string>& x,
                                  double scale = 1.0,
                                  bool color = false) {
    size_t n = x.size();
    size_t dim = floor(SIZE * scale);
    size_t channels = color ? 3 : 1;
    xtensor4d res({n, dim, dim, channels});
    parallelFor(0, n, [&x, &res, scale, color](int i) {
        xtensor3d tmp = process(x[i], scale, color);
        auto view = xt::view(res, i, xt::all(), xt::all(), xt::all());
        view = tmp;
    });
    return res;
}
