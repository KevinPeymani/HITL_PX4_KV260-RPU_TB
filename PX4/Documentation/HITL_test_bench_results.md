# KV260 RPU — HITL Test Bench Results

Measurements from HITL flights of PX4 on the KV260 R5 (`PX4_impl_steps.md` step 8).

Setup:
- PX4 `kv260-rpu` `03c155bbaac`, `amd_kv260-rpu_default` (ddr 1,617,000 B), on R5_0 (lockstep), loaded by remoteproc
- Gazebo Classic 11.10.2 (`Simulation/gazebo-classic`), `hitl_iris.world`, on a native Ubuntu PC (GPU), KV260 on a direct link
- MAVLink: `/dev/ttyRPMSG1` → socat (KV260 Linux) → TCP 5760 → socat → `/tmp/ttyKV260` (container); QGroundControl on the same PC

---

## CPU load during hover (2026-11-03)

`top` in NSH, iris hovering in position hold, uptime 1004 s:

| PID | Task | CPU % | Stack used / size | Priority |
|---|---|---|---|---|
| 156 | `wq:INS0` (EKF2) | 10.55 | 3832 / 5984 | 241 |
| 297 | `mavlink_rcv_if0` | 7.30 | 1840 / 3984 | 175 |
| 142 | `wq:nav_and_controllers` | 6.46 | 1432 / 2224 | 242 |
| 291 | `mavlink_if0` | 5.56 | 1960 / 2792 | 100 |
| 143 | `wq:rate_ctrl` | 4.58 | 2480 / 3128 | 255 |
| 202 | `commander` | 1.38 | 1536 / 3192 | 140 |
| 4 | `rptun` | 0.84 | 488 / 4040 | 224 |
| 1 | `hpwork` | 0.41 | 344 / 1984 | 249 |
| 400 | `top` | 0.28 | 2408 / 4064 | 237 |
| 350 | `navigator` | 0.25 | 1380 / 2176 | 105 |
| 7 | `wq:lp_default` | 0.06 | 1016 / 3480 | 205 |
| 171 | `wq:hp_default` | 0.01 | 852 / 2784 | 237 |
| 136 | `dataman` | 0.00 | 816 / 1968 | 90 |
| 2, 5, 6 | `lpwork`, `nsh_main`, `wq:manager` | 0.00 | 312 / 1984, 2396 / 8152, 328 / 1240 | 50, 100, 255 |

- Total: 37.68 % tasks, 1.34 % scheduler, 60.99 % idle; 17 processes.
- Estimation and control (`INS0`, `nav_and_controllers`, `rate_ctrl`): 21.6 %. MAVLink (both threads): 12.9 %, more than the rate controller. RPMsg (`rptun`): 0.8 %.
- Stacks: all within limits; the fullest are `wq:rate_ctrl` (79 %, 648 B free) and `mavlink_if0` (70 %).

## Controller rates during hover (2026-11-03)

`work_queue status`: the control chain runs at the HIL IMU rate (physics 250 Hz):

| Queue | Item | Rate |
|---|---|---|
| `wq:INS0` | `vehicle_imu` | 249.9 Hz |
| | `ekf2` | 239.1 Hz |
| `wq:rate_ctrl` | `mc_rate_control` | 249.9 Hz |
| | `vehicle_angular_velocity` | 243.2 Hz |
| | `pwm_out_sim` | 240.0 Hz |
| | `control_allocator` | 239.6 Hz |
| `wq:nav_and_controllers` | `mc_att_control` | 249.9 Hz |
| | `vehicle_acceleration` | 250.0 Hz |
| | `sensors` | 243.2 Hz |
| | `mc_hover_thrust_estimator` | 96.3 Hz |
| | `mc_pos_control` | 92.2 Hz |
| | `vehicle_magnetometer` | 80.4 Hz |
| | `flight_mode_manager` | 50.0 Hz |
| | `land_detector` | 48.6 Hz |
| | `vehicle_air_data` | 40.7 Hz |
| | `vehicle_gps_position` | 7.3 Hz |
| `wq:lp_default` | `send_event` | 30.0 Hz (target 30) |
| | `load_mon` | 2.0 Hz (target 2) |
| `wq:hp_default` | `manual_control` | 5.0 Hz |

`rc_update` and `parameters` are at 0 Hz (no RC input; no parameter changes).

## Timing (`perf`, during hover, 2026-11-03)

| Counter | Events | Avg | Min | Max | RMS |
|---|---|---|---|---|---|
| control latency | 268,206 | 767 µs | 315 µs | 4579 µs | 445 µs |
| `ekf2`: EKF update | 103,413 | 429 µs | 300 µs | 1237 µs | 136 µs |
| `commander`: cycle | 99,637 | 204 µs | 69 µs | 5660 µs | 324 µs |
| `navigator` | 22,359 | 113 µs | 52 µs | 3256 µs | 123 µs |
| `flight_mode_manager`: cycle | 53,505 | 108 µs | 91 µs | 933 µs | 53 µs |
| `mc_pos_control`: cycle time | 103,915 | 77 µs | 1 µs | 326 µs | 6 µs |
| `control_allocator`: cycle | 269,148 | 73 µs | 30 µs | 363 µs | 8 µs |
| `sensors` | 272,912 | 50 µs | 20 µs | 934 µs | 6 µs |
| `mc_att_control`: cycle | 267,334 | 43 µs | 30 µs | 330 µs | 10 µs |
| `mc_rate_control`: cycle | 268,205 | 27 µs | 21 µs | 260 µs | 2 µs |
| `vehicle_angular_velocity`: gyro filter | 272,947 | 27 µs | 9 µs | 283 µs | 2 µs |
| `mavlink`: tx run interval | 331,200 | 3383 µs | 2158 µs | 15,916 µs | 802 µs |
| `mavlink`: tx run elapsed | 331,200 | 303 µs | 44 µs | 7963 µs | 378 µs |

- Control latency (gyro sample to actuator output, inside PX4): 0.77 ms average, 4.6 ms worst.
- Later in the same hover (534,982 rate-controller cycles): control latency 775 µs avg, EKF update 428 µs avg; every maximum unchanged (control latency 4579 µs, EKF 1237 µs, `mavlink` tx run interval 15,916 µs), so the worst cases all came before the first `perf` and the averages don't drift.
- No late or overrun counters. `ekf2: IMU message missed` 0; `mavlink`: `send_bytes error` 0, `forwarding error` 0, `STATUSTEXT missed messages` 0.
- `vehicle_imu`: one gyro and one accel data gap; `vehicle_angular_velocity`: one gyro selection change and filter reset. They happened once, before the first `perf`, and didn't recur: a later `perf`, about 18 minutes on (534,982 rate-controller cycles), still shows 1 each.
- `pwm_out_sim` `interval` and `cycle` count 0 events although the work queue shows it at 240 Hz: in HIL mode it doesn't update those counters (**verify**).

## MAVLink link during hover (2026-11-03)

`mavlink status`, instance on `/dev/ttyRPMSG1`:

- tx 16.65 kB/s, `txerr` 0; rx 18.70 kB/s; GCS heartbeat valid.
- From Gazebo (sysid 1, compid 200): 282,048 messages, 256 lost (0.09 %); `HIL_SENSOR` (107) shown at 338.3 Hz while `vehicle_imu` runs at 249.9 Hz, so the per-message rate display is not a rate measurement; `HIL_GPS` (113); heartbeat 1.0 Hz.
- From QGroundControl (sysid 255, compid 190): 1,361 messages, 156,742 "lost". PX4 counts a loss for each skipped sequence number per sender: QGC's numbers jump by about 115 between the messages that arrive, so QGC sends messages that never reach PX4 (dropped in Gazebo's relay or sent on another link, **verify**). This gives the overall `rx loss` of 35.6 %; the flight is unaffected. Its heartbeat is shown at 298.3 Hz, last 0.87 s ago (same display quirk).
- MAVLink ping (PX4 to QGroundControl and back, through RPMsg, Linux, both socats, TCP, Gazebo's relay and UDP): last 1.47 ms, mean 2.16 ms, min 0.62 ms, max 8.31 ms, 0 dropped.

## uORB traffic during hover (`uorb top`, 2026-11-03)

113 topics, 6310 publications/s, 443.1 kB/s. Topics with traffic (rate in Hz, #Q = queue length, size in bytes):

| Topic | Subs | Rate | #Q | Size |
|---|---|---|---|---|
| `actuator_motors` | 1 | 250 | 1 | 72 |
| `actuator_outputs` | 1 | 250 | 1 | 80 |
| `actuator_outputs_sim` | 1 | 250 | 1 | 80 |
| `battery_status` | 2 | 250 | 1 | 168 |
| `sensor_accel` | 4 | 250 | 8 | 48 |
| `sensor_combined` | 1 | 250 | 1 | 48 |
| `sensor_gyro` | 4 | 250 | 8 | 48 |
| `sensors_status_imu` | 1 | 250 | 1 | 96 |
| `vehicle_acceleration` | 1 | 250 | 1 | 32 |
| `vehicle_angular_velocity` | 5 | 250 | 1 | 40 |
| `vehicle_attitude` | 9 | 250 | 1 | 56 |
| `vehicle_imu` | 2 | 250 | 1 | 64 |
| `vehicle_rates_setpoint` | 2 | 250 | 1 | 40 |
| `vehicle_thrust_setpoint` | 4 | 250 | 1 | 32 |
| `vehicle_torque_setpoint` | 1 | 250 | 1 | 32 |
| `control_allocator_status` | 2 | 137 | 1 | 56 |
| `estimator_status` | 6 | 101 | 1 | 136 |
| `vehicle_attitude_setpoint` | 3 | 101 | 1 | 40 |
| `vehicle_global_position` | 9 | 101 | 1 | 72 |
| `vehicle_local_position` | 21 | 101 | 1 | 192 |
| `vehicle_local_position_setpoint` | 3 | 101 | 1 | 64 |
| `hover_thrust_estimate` | 3 | 100 | 1 | 48 |
| `sensor_mag` | 2 | 84 | 4 | 48 |
| `trajectory_setpoint` | 2 | 50 | 1 | 64 |
| `vehicle_constraints` | 1 | 50 | 1 | 24 |
| `sensor_baro` | 3 | 41 | 4 | 40 |
| `sensors_status_baro` | 1 | 41 | 1 | 64 |
| `vehicle_air_data` | 5 | 21 | 1 | 40 |
| `vehicle_magnetometer` | 1 | 14 | 1 | 40 |
| `vehicle_imu_status` | 4 | 9 | 1 | 136 |
| `sensors_status_gnss` | 3 | 8 | 1 | 120 |
| `sensor_gnss` | 3 | 6 | 1 | 136 |
| `vehicle_gnss` | 7 | 6 | 1 | 176 |
| `geofence_result` | 1 | 4 | 1 | 16 |
| `telemetry_status` | 2 | 3 | 1 | 96 |
| `actuator_armed`, `cpuload`, `failsafe_flags`, `failure_detector_status`, `navigator_status`, `vehicle_control_mode`, `vehicle_status` | 1–27 | 2 | 1 | 16–104 |
| `estimator_sensor_bias`, `estimator_status_flags`, `rtl_time_estimate`, `vehicle_land_detected` | 1–14 | 1 | 1 | 24–120 |

- IMU path (`sensor_gyro`/`sensor_accel` → `vehicle_imu` → `vehicle_attitude`) and the rate loop (`vehicle_rates_setpoint` → torque/thrust setpoints → `actuator_motors` → `actuator_outputs_sim`) at 250 Hz; EKF outputs (`estimator_status`, `vehicle_local_position`) and the attitude/position setpoints at 101 Hz.
- Most subscribers: `vehicle_status` (27, at 2 Hz), `vehicle_local_position` (21), `vehicle_control_mode` and `vehicle_land_detected` (14).
