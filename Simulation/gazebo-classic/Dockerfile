# Gazebo Classic 11 with the PX4 HITL plugins, models and worlds, for the KV260 RPU.
# Self-contained: no PX4 tree needed. run.sh builds it.
FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG USER_UID=1000
ARG USER_GID=1000

# Commits pinned by PX4-Autopilot (Tools/simulation/gazebo-classic/sitl_gazebo-classic, src/modules/mavlink/mavlink).
ARG SITL_GAZEBO_COMMIT=f835e077d06eaf09a57d5152fcfb85244b53b77a
ARG MAVLINK_COMMIT=2e2b6af99084e4fde9bb304c84bb9253a1a98b6f
# MAVLink dialect of the firmware (CONFIG_MAVLINK_DIALECT, default common).
ARG MAVLINK_DIALECT=common
ARG HITL_SERIAL_DEVICE=/tmp/ttyKV260

RUN apt-get update && apt-get install -y --no-install-recommends \
        gazebo libgazebo-dev \
        build-essential cmake ninja-build git ca-certificates \
        python3 python3-jinja2 python3-numpy python3-lxml python3-pip \
        libboost-system-dev libboost-thread-dev libboost-filesystem-dev \
        libopencv-dev libeigen3-dev libprotobuf-dev protobuf-compiler \
        libtinyxml-dev \
        libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
        gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
        gstreamer1.0-plugins-bad gstreamer1.0-libav \
        qtbase5-dev \
        socat mesa-utils \
    && rm -rf /var/lib/apt/lists/*

# MAVLink C headers in /usr/local/include/mavlink, where the plugin's FindMAVLink looks.
RUN git clone https://github.com/mavlink/mavlink.git /tmp/mavlink \
    && git -C /tmp/mavlink checkout ${MAVLINK_COMMIT} \
    && git -C /tmp/mavlink submodule update --init pymavlink \
    && pip3 install --no-cache-dir fastcrc \
    && cd /tmp/mavlink \
    && python3 -m pymavlink.tools.mavgen --lang C --wire-protocol 2.0 \
        --output /usr/local/include/mavlink message_definitions/v1.0/${MAVLINK_DIALECT}.xml \
    && rm -rf /tmp/mavlink

RUN git clone https://github.com/PX4/PX4-SITL_gazebo-classic.git /opt/sitl_gazebo-classic \
    && git -C /opt/sitl_gazebo-classic checkout ${SITL_GAZEBO_COMMIT} \
    && git -C /opt/sitl_gazebo-classic submodule update --init --recursive

# Same options as PX4's sitl_targets_gazebo-classic.cmake, without the ROS models.
# Only the models and the plugins iris_hitl and hitl_iris.world load: the camera
# manager plugin doesn't compile against PX4's pinned MAVLink (VIDEO_STREAM_STATUS gained vfov).
RUN cmake -S /opt/sitl_gazebo-classic -B /opt/sitl_gazebo-classic/build -G Ninja \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo -DSEND_ODOMETRY_DATA=ON \
    && cmake --build /opt/sitl_gazebo-classic/build --target models_gen \
        gazebo_mavlink_interface gazebo_motor_model gazebo_multirotor_base_plugin \
        gazebo_imu_plugin gazebo_gps_plugin gazebo_magnetometer_plugin \
        gazebo_barometer_plugin gazebo_groundtruth_plugin

RUN sed -i "s|<serialDevice>.*</serialDevice>|<serialDevice>${HITL_SERIAL_DEVICE}</serialDevice>|" \
        /opt/sitl_gazebo-classic/models/iris_hitl/iris_hitl.sdf \
    && grep -q "<serialDevice>${HITL_SERIAL_DEVICE}</serialDevice>" \
        /opt/sitl_gazebo-classic/models/iris_hitl/iris_hitl.sdf

# Gazebo's own paths, then the plugins and models (as PX4's setup_gazebo.bash).
RUN printf '%s\n' \
        'source /usr/share/gazebo/setup.sh' \
        'export GAZEBO_PLUGIN_PATH=$GAZEBO_PLUGIN_PATH:/opt/sitl_gazebo-classic/build' \
        'export GAZEBO_MODEL_PATH=$GAZEBO_MODEL_PATH:/opt/sitl_gazebo-classic/models' \
        'export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/opt/sitl_gazebo-classic/build' \
        > /etc/profile.d/sitl_gazebo.sh \
    && echo 'source /etc/profile.d/sitl_gazebo.sh' >> /etc/bash.bashrc

# Same UID as the host user, for access to the WSLg sockets.
RUN groupadd -g ${USER_GID} px4 \
    && useradd -m -u ${USER_UID} -g ${USER_GID} -s /bin/bash px4

USER px4
WORKDIR /opt/sitl_gazebo-classic
CMD ["bash"]
