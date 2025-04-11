# Chris_KSP_Lib
适用于KSP原版或RSS/RO环境的KOS脚本。

## MOD 列表

- KSP-1.12.5
- kOS: Scriptable Autopilot System-1.4.0.0
- Trajectories-v2.4.5.3  (For pegland)
- WaypointManager (Recommended for pegland)

## PEG 着陆

`pegland`是这个脚本包中最精彩的程序，从1960s NASA为Surveyor项目开发的PEG发射制导算法修改而来，实现真空环境下燃料最优的定点着陆，误差在100 m内。

```kOS
run pegland.  // 默认模式
run pegland(1).  // 紧急模式，无需等待点火位置，直接着陆
```

使用该程序需要：

1. 确保航天器满足着陆要求：充足的Δv，末段推重比范围包含1

2. 合适的初始轨道和着陆点，着陆点大概在轨道近地点下方

3. 通过Trajectoties mod窗口设置着陆目标。强烈推荐组合WaypointManager使用：
   1. 通过WaypointManager在地图中创建导航点，并设置到目标的导航

      ![](./pictures/waypointmanager.png)

   2. 在Trajectories中采用激活的导航点作为着陆目标

      ![](./pictures/trajectories.png)

`pegland`默认模式下有三个阶段：

1. 点火位置估计：迭代计算点火位置、时间和初始控制参数。

   ![](./pictures/waitingphase.png)

   ```
   Time to ignition: 点火倒计时
   T: 估计着陆燃烧时间
   dv: 估计着陆燃烧Δv
   dtheta: 点火开始位置与目标位置距离（中心天体极坐标下的角度）
   A, B: 俯仰控制参数
   ```

2. 动力下降：点火-60s自动调整姿态，点火-2s执行燃料沉底并点火，燃烧期间迭代更新控制参数。在着陆过程中油门始终高于引擎允许的最低油门，因此不会熄火。

   ![](./pictures/brakingphase.png)

   ```
   Iter: 计算迭代次数
   T: 估计剩余燃烧时间
   dv: 估计剩余燃烧Δv
   A: 俯仰控制参数
   thro: 油门
   E: 着陆位置误差（中心天体极坐标下的角度），正值表示着陆点在目标后方
   ```

3. 末段着陆：在目标点上方大约200m处调整姿态向上，消除水平速度并着陆。这一阶段没有瞄准目标点，因此引入了主要的着陆误差。我会在后续更新中加入更完善的末端着陆制导算法。

如果用户在下降途中修改了着陆点，可以中断着陆程序，以紧急模式重新运行。此时程序将直接点火下降，而无需等待运行到点火位置。

## 执行机动节点

`exe_node`和`exe_pulse_node`是两个适用于Principia环境下的高精度机动节点执行程序。在Principia中规划的机动节点考虑了燃烧过程，在时间较长的机动节点中，期间燃烧方向和位置的变化，以及天体引力的影响不可忽略。另外，RO发动机的推力不恒定，导致燃烧计时无法精确反映Δv。`exe_node`和`exe_pulse_node` 不采用计时的方法，而是通过维护一个Δv积分器直接精确监测燃烧过程中积攒的Δv.

- `exe_node`执行Principia机动节点，点火从节点位置开始，始终跟随目标燃烧矢量
- `exe_pulse_node`执行stock机动节点，点火从节点位置前`T/2`时刻开始

## 规划轨道圆化机动

执行`circularize`会在远地点规划一个加速机动节点以圆化轨道。`circularize(1)`在近地点规划减速机动。

