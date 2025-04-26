#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <stdbool.h>

/* Проверяет, находится ли точка (x, y) в пределах углового сектора радара */
bool is_in_sector(long long target_x, long long target_y, long long radar_x, long long radar_y,
                  long long radar_dir, long long radar_angle) {
    long long diff_x = target_x - radar_x;
    long long diff_y = target_y - radar_y;
    
    // Вычисление угла к цели в градусах
    double direction_to_target = atan2((double)diff_y, (double)diff_x) * 180.0 / M_PI;
    if (direction_to_target < 0) {
        direction_to_target += 360;
    }

    // Вычисление относительного угла
    double relative_direction = direction_to_target - radar_dir;
    if (relative_direction > 180) {
        relative_direction -= 360;
    }
    if (relative_direction < -180) {
        relative_direction += 360;
    }

    // Проверка, находится ли относительный угол в пределах сектора
    return (relative_direction >= -radar_angle / 2) && (relative_direction <= radar_angle / 2);
}

int main(int argc, char* argv[]) {
    if (argc != 7) {
        fprintf(stderr, "Usage: %s x y radar_x radar_y radar_dir radar_angle\n", argv[0]);
        return 1;
    }

    long long target_x = atoll(argv[1]);
    long long target_y = atoll(argv[2]);
    long long radar_x = atoll(argv[3]);
    long long radar_y = atoll(argv[4]);
    long long radar_dir = atoll(argv[5]);
    long long radar_angle = atoll(argv[6]);

    printf("%d\n", is_in_sector(target_x, target_y, radar_x, radar_y, radar_dir, radar_angle));

    return 0;
}