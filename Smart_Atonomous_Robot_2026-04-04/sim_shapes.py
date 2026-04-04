import math
import numpy as np

def get_cv(points):
    minX = min(p[0] for p in points)
    maxX = max(p[0] for p in points)
    minY = min(p[1] for p in points)
    maxY = max(p[1] for p in points)
    
    cx = (minX + maxX) / 2
    cy = (minY + maxY) / 2
    
    r_list = [math.sqrt((p[0]-cx)**2 + (p[1]-cy)**2) for p in points]
    meanR = sum(r_list) / len(r_list)
    varR = sum((r - meanR)**2 for r in r_list) / len(r_list)
    return math.sqrt(varR) / (meanR + 0.001)

def circle():
    pts = []
    for i in range(100):
        t = i / 100 * 2 * math.pi
        pts.append((math.cos(t), math.sin(t)))
    return pts

def square():
    pts = []
    # from -1 to 1
    for i in range(25):
        pts.append((-1 + 2 * i/25, -1))
    for i in range(25):
        pts.append((1, -1 + 2 * i/25))
    for i in range(25):
        pts.append((1 - 2 * i/25, 1))
    for i in range(25):
        pts.append((-1, 1 - 2 * i/25))
    return pts

def hexagon():
    pts = []
    corners = [(math.cos(t), math.sin(t)) for t in [i * 2 * math.pi / 6 for i in range(6)]]
    for i in range(6):
        c1 = corners[i]
        c2 = corners[(i+1)%6]
        for j in range(17):
            pts.append((c1[0] + (c2[0]-c1[0])*j/17, c1[1] + (c2[1]-c1[1])*j/17))
    return pts

def triangle():
    pts = []
    corners = [(math.cos(t), math.sin(t)) for t in [i * 2 * math.pi / 3 for i in range(3)]]
    for i in range(3):
        c1 = corners[i]
        c2 = corners[(i+1)%3]
        for j in range(33):
            pts.append((c1[0] + (c2[0]-c1[0])*j/33, c1[1] + (c2[1]-c1[1])*j/33))
    return pts

print("Circle:", get_cv(circle()))
print("Square:", get_cv(square()))
print("Hexagon:", get_cv(hexagon()))
print("Triangle:", get_cv(triangle()))
