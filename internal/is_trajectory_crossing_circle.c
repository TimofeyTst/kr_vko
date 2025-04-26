#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <stdbool.h>

/* Вычисляет евклидово расстояние между двумя точками (x1, y1) и (x2, y2) */
long long calculate_euclidean_distance(long long p1_x, long long p1_y, long long p2_x, long long p2_y) {
    long long delta_x = p2_x - p1_x;
    long long delta_y = p2_y - p1_y;
    return llround(sqrt((double)(delta_x * delta_x + delta_y * delta_y)));
}

/* Проверяет пересечение траектории с заданным радиусом вокруг точки */
bool is_trajectory_crossing_circle(long long start_x, long long start_y, long long end_x, long long end_y, 
                                   long long center_x, long long center_y, long long circle_radius) {
    long long line_dx = end_x - start_x;
    long long line_dy = end_y - start_y;

    // Вычисление расстояния от центра до линии
    long long numerator = llabs((line_dy * center_x) - (line_dx * center_y) + (end_x * start_y) - (end_y * start_x));
    double line_length = sqrt((double)(line_dx * line_dx + line_dy * line_dy));
    double dist_to_line = numerator / line_length;

    // Расстояния от начала и конца линии до центра
    long long start_to_center = calculate_euclidean_distance(start_x, start_y, center_x, center_y);
    long long end_to_center = calculate_euclidean_distance(end_x, end_y, center_x, center_y);

    // Проверяем, пересекает ли линия круг и движется ли она в сторону центра
    return (dist_to_line <= circle_radius) && (end_to_center < start_to_center);
}

int main(int argc, char* argv[]) {
    if (argc != 8) {
        fprintf(stderr, "Usage: %s start_x start_y end_x end_y center_x center_y radius\n", argv[0]);
        return 1;
    }

    long long start_x = atoll(argv[1]);
    long long start_y = atoll(argv[2]);
    long long end_x = atoll(argv[3]);
    long long end_y = atoll(argv[4]);
    long long center_x = atoll(argv[5]);
    long long center_y = atoll(argv[6]);
    long long radius = atoll(argv[7]);

    printf("%d\n", is_trajectory_crossing_circle(start_x, start_y, end_x, end_y, center_x, center_y, radius));
    return 0;
}