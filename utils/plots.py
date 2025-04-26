import sqlite3
import matplotlib.pyplot as plt
import matplotlib.patches as patches
import os

DB_PATH = os.path.join('..', 'db', 'vkr.db')

def fetch_detections():
    """Извлекаем данные обнаружения из базы данных."""
    with sqlite3.connect(DB_PATH) as conn:
        cursor = conn.cursor()
        query = """
        SELECT d.x, d.y, t.ttype, s.name
        FROM detections d
        JOIN targets t ON d.target_id = t.id
        JOIN systems s ON d.system_id = s.id
        """
        cursor.execute(query)
        return cursor.fetchall()

def render_detection_map():
    """Отображает карту обнаружений."""
    detections = fetch_detections()

    if not detections:
        print("Данные отсутствуют для отображения.")
        return

    fig, ax = plt.subplots(figsize=(14, 10))

    # ZRDN
    zrdn = [
        {'center': (5050000, 3750000), 'radius': 600000, 'color': "#5fba7d"}, # green
        {'center': (2900000, 3500000), 'radius': 400000, 'color': "#5fba7d"}, 
        {'center': (2600000, 6100000), 'radius': 550000, 'color': "#5fba7d"}
    ]
    
    spro = [
        {'center': (3250000, 5250000), 'radius': 1400000, 'color': "#e57373"}
    ]

    for zone in zrdn:
        circle = plt.Circle(zone['center'], zone['radius'], color=zone['color'], alpha=0.4, label='ЗРДН')
        ax.add_patch(circle)
    
    for zone in spro:
        circle = plt.Circle(zone['center'], zone['radius'], color=zone['color'], alpha=0.4, label='СПРО')
        ax.add_patch(circle)

    # Секторы обзора
    rls = [
        {'center': (2500000, 6500000), 'radius': 6000000, 'direction': 90, 'angle': 90, 'color': "#42a5f5"}, # blue
        {'center': (12000000, 5000000), 'radius': 3500000, 'direction': 90, 'angle': 120, 'color': "#42a5f5"},
        {'center': (3900000, 5250000), 'radius': 4000000, 'direction': 270, 'angle': 200, 'color': "#42a5f5"}
    ]

    for sector in rls:
        start_angle = sector['direction'] - sector['angle'] / 2
        end_angle = sector['direction'] + sector['angle'] / 2
        wedge = patches.Wedge(sector['center'], sector['radius'], start_angle, end_angle, color=sector['color'], alpha=0.15, label='РЛС')
        ax.add_patch(wedge)

    # Цветовые обозначения для различных типов целей
    target_color_map = {
        "ББ БР": "red",
        "Крылатая ракета": "gold",
        "Самолет": "steelblue"
    }

    markers_by_system = {
        "ЗРДН1": "o",  # кружочки
        "ЗРДН2": "o",  # кружочки
        "ЗРДН3": "o",  # кружочки
        "СПРО": "P",   # крестики
        "РЛС1": "D",   # ромбы
        "РЛС2": "D",   # ромбы
        "РЛС3": "D",   # ромбы
    }

    for x, y, target_type, system_name in detections:
        color = target_color_map.get(target_type, "grey") # по умолчанию серый
        marker = markers_by_system.get(system_name, "x") # по умолчанию крестики
        plt.scatter(x, y, c=color, marker=marker, edgecolor="black", alpha=0.8, s=60, label=target_type)

    # Настройка границ и пользовательских меток
    plt.xlim(0, 13000000)
    plt.ylim(0, 9000000)
    plt.xlabel("Координата X")
    plt.ylabel("Координата Y")
    plt.title("Обнаруженные цели")

    # Деления на графике
    ax.set_xticks(range(0, 14000000, 1000000))
    ax.set_yticks(range(0, 10000000, 1000000))
    ax.ticklabel_format(style="plain")

    # Устранение дублирования меток в легенде
    handles, labels = plt.gca().get_legend_handles_labels()
    by_labels = dict(zip(labels, handles))
    plt.legend(by_labels.values(), by_labels.keys(), loc="lower right", frameon=False)

    plt.grid(True, linestyle="--", linewidth=0.6)
    plt.show()
/home/timofeytst/tmp/kr_vko/utils
if __name__ == "__main__":
    render_detection_map()