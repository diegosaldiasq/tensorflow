// RUN: tf-opt %s -split-input-file -verify-diagnostics -tf-tpu-extract-outside-compilation | FILECHECK_OPTS="" FileCheck %s

// Tests that missing `_xla_outside_compilation` attribute value results in an error.

module attributes {tf.versions = {producer = 888 : i32}, tf.devices = ["/job:worker/replica:0/task:0/device:CPU:0", "/job:worker/replica:0/task:0/device:TPU_SYSTEM:0", "/job:worker/replica:0/task:0/device:TPU:0"]} {
  // Tests that TPU cluster with no outside compilation does not generate parallel_execute.

  // CHECK-LABEL: func @no_outside_compilation
  func @no_outside_compilation() -> tensor<?xi32> {
    %0 = "tf_device.cluster"() ( {
      %1 = "tf.A"() : () -> tensor<?xi32>
      %2 = "tf.B"(%1) : (tensor<?xi32>) -> tensor<?xi32>
      tf_device.return %2 : tensor<?xi32>
    }) {num_cores_per_replica = 1, topology =  "", device_assignment =  []} : () -> tensor<?xi32>
    return %0 : tensor<?xi32>
  }

  // CHECK-NOT: "tf_device.parallel_execute"

  // Tests extraction of a single outside compiled cluster with no input or output dependecies.

  // CHECK-LABEL: func @nodep_single_outside_compilation
  func @nodep_single_outside_compilation() -> () {
     // CHECK: "tf_device.parallel_execute"
     // CHECK-NEXT: "tf_device.launch"
     // CHECK-NEXT: "tf.B"
     // CHECK-NOT: _xla_outside_compilation
     // CHECK-NEXT:   tf_device.return
     // CHECK-NEXT: device = "/job:worker/replica:0/task:0/device:CPU:0"
     // CHECK: "tf_device.cluster"
     // CHECK-NEXT: "tf.A"
     // CHECK: device_assignment =  [], num_cores_per_replica = 1 : i64, topology =  ""
    "tf_device.cluster"() ( {
      "tf.A"() : () -> ()
      "tf.B"() {_xla_outside_compilation = "cluster1"} : () -> ()
      "tf.C"() : () -> ()
      tf_device.return
    }) {num_cores_per_replica = 1, topology =  "", device_assignment =  []} : () -> ()
    return
  }

  // Tests extraction of a single outside compiled cluster with multiple ops and no input or output dependecies.

  // CHECK-LABEL: func @nodep_single_cluster_multiple_ops_outside_compilation
  func @nodep_single_cluster_multiple_ops_outside_compilation() -> () {
     // CHECK: "tf_device.parallel_execute"
     // CHECK-NEXT: "tf_device.launch"
     // CHECK-NEXT: "tf.B"
     // CHECK-NEXT: "tf.C"
     // CHECK-NEXT: "tf.D"
     // CHECK-NOT: _xla_outside_compilation
     // CHECK: "tf_device.cluster"
     // CHECK-NEXT: "tf.A"
     // CHECK-NEXT: "tf.E"
     // CHECK: device_assignment =  [], num_cores_per_replica = 1 : i64, topology =  ""
    "tf_device.cluster"() ( {
      "tf.A"() : () -> ()
      "tf.B"() {_xla_outside_compilation = "cluster1"} : () -> ()
      "tf.C"() {_xla_outside_compilation = "cluster1"} : () -> ()
      "tf.D"() {_xla_outside_compilation = "cluster1"} : () -> ()
      "tf.E"() : () -> ()
      tf_device.return
    }) {num_cores_per_replica = 1, topology =  "", device_assignment =  []} : () -> ()
    return
  }

  // Tests extraction of a multiple outside compiled clusters with no input or output dependecies.

  // CHECK-LABEL: func @nodep_multiple_outside_compilation
  func @nodep_multiple_outside_compilation() -> () {
     // CHECK: "tf_device.parallel_execute"
     // CHECK-COUNT-2: "tf_device.launch"
     // CHECK: "tf_device.cluster"
    "tf_device.cluster"() ( {
      "tf.A"() : () -> ()
      "tf.B"() {_xla_outside_compilation = "cluster1"} : () -> ()
      "tf.C"() : () -> ()
      "tf.D"() {_xla_outside_compilation = "cluster2"} : () -> ()
      "tf.E"() : () -> ()
      tf_device.return
    }) {num_cores_per_replica = 1, topology =  "", device_assignment =  []} : () -> ()
    return
  }

  // Tests extraction of a single outside compiled cluster with single TPU cluster return.

  // CHECK-LABEL: func @single_tpu_return_single_outside_compilation
  func @single_tpu_return_single_outside_compilation(%arg0: tensor<?xi32>) -> tensor<?xi32> {
    %0 = "tf.A"(%arg0) : (tensor<?xi32>) -> tensor<?xi32>
    // CHECK:      %[[REPLICATE:[0-9]*]]:2 = tf_device.replicate
    // CHECK:        %[[PARALLEL_EXECUTE_OUTPUT:[0-9]*]] = "tf_device.parallel_execute"
    // CHECK-NEXT:     "tf_device.launch"
    // CHECK-NEXT:       "tf.B"
    // CHECK-NEXT:       tf_device.return
    // CHECK-NEXT:     device = "TPU_REPLICATED_HOST"
    // CHECK:          %[[TPU_CLUSTER_OUTPUT:[0-9]*]] = "tf_device.cluster"
    // CHECK:            tf_device.return
    // CHECK:          tf_device.return %[[TPU_CLUSTER_OUTPUT]]
    // CHECK:        tf_device.return %[[PARALLEL_EXECUTE_OUTPUT]]
    %1:2 = tf_device.replicate([%0, %arg0] as %ri_0: tensor<?xi32>) {n = 2 : i32} {
      %2 = "tf_device.cluster"() ( {
        "tf.A"() : () -> ()
        "tf.B"() {_xla_outside_compilation = "cluster1"} : () -> ()
        %3 = "tf.C"() : () -> tensor<?xi32>
        tf_device.return %3 : tensor<?xi32>
      }) {num_cores_per_replica = 1, topology =  "", device_assignment =  []} : () -> tensor<?xi32>
      tf_device.return %2 : tensor<?xi32>
    }

    return %1 : tensor<?xi32>
  }

  // Tests extraction of a single outside compiled cluster with multiple TPU cluster return.

  // CHECK-LABEL: func @multiple_tpu_return_single_outside_compilation
  func @multiple_tpu_return_single_outside_compilation(%arg0: tensor<?xi32>) -> tensor<?xf32> {
    %0 = "tf.A"(%arg0) : (tensor<?xi32>) -> tensor<?xi32>
    // CHECK:      %[[REPLICATE:[0-9]*]]:4 = tf_device.replicate
    // CHECK:        %[[PARALLEL_EXECUTE_OUTPUT:[0-9]*]]:2  = "tf_device.parallel_execute"
    // CHECK-NEXT:     "tf_device.launch"
    // CHECK:          %[[TPU_CLUSTER_OUTPUT:[0-9]*]]:2 = "tf_device.cluster"
    // CHECK:            tf_device.return
    // CHECK:          tf_device.return %[[TPU_CLUSTER_OUTPUT]]
    // CHECK:        tf_device.return %[[PARALLEL_EXECUTE_OUTPUT]]
    %1:4 = tf_device.replicate([%0, %arg0] as %ri_0: tensor<?xi32>) {n = 2 : i32} {
      %2, %3 = "tf_device.cluster"() ( {
        %4 = "tf.A"() : () -> tensor<?xf32>
        "tf.B"() {_xla_outside_compilation = "cluster1"} : () -> ()
        %5 = "tf.C"() : () -> tensor<?xi32>
        tf_device.return %4, %5  : tensor<?xf32>, tensor<?xi32>
      }) {num_cores_per_replica = 1, topology =  "", device_assignment =  []} : () -> (tensor<?xf32>, tensor<?xi32>)
      tf_device.return %2, %3 : tensor<?xf32>, tensor<?xi32>
    }

    return %1 : tensor<?xf32>
  }

  // Tests extraction of a single outside compiled cluster with single device->host input.

  // CHECK-LABEL: func @single_outside_compiled_input_single_outside_compilation
  func @single_outside_compiled_input_single_outside_compilation(%arg0: tensor<?xi32>) -> tensor<?xi32> {
    %0 = "tf.A"(%arg0) : (tensor<?xi32>) -> tensor<?xi32>
    // CHECK:      %[[REPLICATE:[0-9]*]]:2 = tf_device.replicate
    // CHECK:        %[[PARALLEL_EXECUTE_OUTPUT:[0-9]*]] = "tf_device.parallel_execute"
    // CHECK-NEXT:     "tf_device.launch"
    // CHECK:            %[[PROGRAM_OUTPUT:[a-z_0-9]*]] = "tf._TPUCompileMlirPlaceholderProgramKey"
    // CHECK:            %[[RECV_OUTPUT:[0-9]*]] = "tf._XlaRecvAtHost"(%[[PROGRAM_OUTPUT]])
    // CHECK-SAME:       key = "host_compute_channel_cluster1_args"
    // CHECK:            "tf.B"(%[[RECV_OUTPUT]])
    // CHECK:          "tf_device.cluster"
    // CHECK:            %[[A_OUTPUT:[0-9]*]] = "tf.A"
    // CHECK:            "tf._XlaHostComputeMlir"(%[[A_OUTPUT]])
    // CHECK-SAME:       send_key = "host_compute_channel_cluster1_args"
    %1:2 = tf_device.replicate([%0, %arg0] as %ri_0: tensor<?xi32>) {n = 2 : i32} {
      %2 = "tf_device.cluster"() ( {
        %3 = "tf.A"() : () -> (tensor<?xi32>)
        "tf.B"(%3) {_xla_outside_compilation = "cluster1"} : (tensor<?xi32>) -> ()
        %4 = "tf.C"() : () -> tensor<?xi32>
        tf_device.return %4 : tensor<?xi32>
      }) {num_cores_per_replica = 1, topology =  "", device_assignment =  []} : () -> tensor<?xi32>
      tf_device.return %2 : tensor<?xi32>
    }

    return %1 : tensor<?xi32>
  }

  // Tests extraction of a single outside compiled cluster with single host->device output.

  // CHECK-LABEL: func @single_outside_compiled_output_single_outside_compilation
  func @single_outside_compiled_output_single_outside_compilation(%arg0: tensor<?xi32>) -> tensor<?xi32> {
    %0 = "tf.A"(%arg0) : (tensor<?xi32>) -> tensor<?xi32>
    // CHECK:      %[[REPLICATE:[0-9]*]]:2 = tf_device.replicate
    // CHECK:        %[[PARALLEL_EXECUTE_OUTPUT:[0-9]*]] = "tf_device.parallel_execute"
    // CHECK-NEXT:     "tf_device.launch"
    // CHECK:            %[[PROGRAM_OUTPUT:[a-z_0-9]*]] = "tf._TPUCompileMlirPlaceholderProgramKey"
    // CHECK:            "tf._XlaRecvAtHost"(%[[PROGRAM_OUTPUT]])
    // CHECK-SAME:       key = "host_compute_channel_cluster1_args"
    // CHECK:            %[[B_OUTPUT:[0-9]*]] = "tf.B"()
    // CHECK:            "tf._XlaSendFromHost"(%[[B_OUTPUT]], %[[PROGRAM_OUTPUT]])
    // CHECK-SAME:       key = "host_compute_channel_cluster1_retvals"
    // CHECK:         "tf_device.cluster"
    // CHECK:           %[[A_OUTPUT:[0-9]*]] = "tf.A"
    // CHECK:           %[[HOST_OUTPUT:[0-9]*]] = "tf._XlaHostComputeMlir"()
    // CHECK-SAME:      recv_key = "host_compute_channel_cluster1_retvals"
    // CHECK-SAME:      send_key = "host_compute_channel_cluster1_args"
    // CHECK:           "tf.C"(%[[HOST_OUTPUT]])
    %1:2 = tf_device.replicate([%0, %arg0] as %ri_0: tensor<?xi32>) {n = 2 : i32} {
      %2 = "tf_device.cluster"() ( {
        %3 = "tf.A"() : () -> (tensor<?xi32>)
        %4 = "tf.B"() {_xla_outside_compilation = "cluster1"} : () -> (tensor<?xi32>)
        %5 = "tf.C"(%4) : (tensor<?xi32>) -> tensor<?xi32>
        tf_device.return %5 : tensor<?xi32>
      }) {num_cores_per_replica = 1, topology =  "", device_assignment =  []} : () -> tensor<?xi32>
      tf_device.return %2 : tensor<?xi32>
    }

    return %1 : tensor<?xi32>
  }

  // Tests extraction of a single outside compiled cluster host output returned by TPU cluster.

  // CHECK-LABEL: func @return_host_output_outside_compilation
  func @return_host_output_outside_compilation(%arg0: tensor<?xi32>) -> tensor<?xi32> {
    %0 = "tf.A"(%arg0) : (tensor<?xi32>) -> tensor<?xi32>
    // CHECK:      %[[REPLICATE:[0-9]*]]:2 = tf_device.replicate
    // CHECK:        %[[PARALLEL_EXECUTE_OUTPUT:[0-9]*]] = "tf_device.parallel_execute"
    // CHECK-NEXT:     "tf_device.launch"
    // CHECK:            %[[PROGRAM_OUTPUT:[a-z_0-9]*]] = "tf._TPUCompileMlirPlaceholderProgramKey"
    // CHECK:            %[[RECV_OUTPUT:[0-9]*]] = "tf._XlaRecvAtHost"(%[[PROGRAM_OUTPUT]])
    // CHECK:            %[[B_OUTPUT:[0-9]*]] = "tf.B"(%[[RECV_OUTPUT]])
    // CHECK:            "tf._XlaSendFromHost"(%[[B_OUTPUT]], %[[PROGRAM_OUTPUT]])
    // CHECK-SAME:       key = "host_compute_channel_cluster1_retvals"
    // CHECK:          "tf_device.cluster"
    // CHECK:            %[[A_OUTPUT:[0-9]*]] = "tf.A"
    // CHECK:            %[[HOST_OUTPUT:[0-9]*]] = "tf._XlaHostComputeMlir"(%[[A_OUTPUT]])
    // CHECK-SAME:       recv_key = "host_compute_channel_cluster1_retvals"
    // CHECK:            tf_device.return %[[HOST_OUTPUT]]
    %1:2 = tf_device.replicate([%0, %arg0] as %ri_0: tensor<?xi32>) {n = 2 : i32} {
      %2 = "tf_device.cluster"() ( {
        %3 = "tf.A"() : () -> (tensor<?xi32>)
        %4 = "tf.B"(%3) {_xla_outside_compilation = "cluster1"} : (tensor<?xi32>) -> (tensor<?xi32>)
        %5 = "tf.C"(%3) : (tensor<?xi32>) -> (tensor<?xi32>)
        tf_device.return %4 : tensor<?xi32>
      }) {num_cores_per_replica = 1, topology =  "", device_assignment =  []} : () -> tensor<?xi32>
      tf_device.return %2 : tensor<?xi32>
    }

    return %1 : tensor<?xi32>
  }

  // Tests extraction of a single outside compiled cluster with single input/output.

  // CHECK-LABEL: func @single_outside_compiled_input_output_single_outside_compilation
  func @single_outside_compiled_input_output_single_outside_compilation(%arg0: tensor<?xi32>) -> tensor<?xi32> {
    %0 = "tf.A"(%arg0) : (tensor<?xi32>) -> tensor<?xi32>
    // CHECK:      %[[REPLICATE:[0-9]*]]:2 = tf_device.replicate
    // CHECK:        %[[PARALLEL_EXECUTE_OUTPUT:[0-9]*]] = "tf_device.parallel_execute"
    // CHECK-NEXT:     "tf_device.launch"
    // CHECK:            %[[PROGRAM_OUTPUT:[a-z_0-9]*]] = "tf._TPUCompileMlirPlaceholderProgramKey"
    // CHECK:            %[[RECV_OUTPUT:[0-9]*]] = "tf._XlaRecvAtHost"(%[[PROGRAM_OUTPUT]])
    // CHECK:            %[[B_OUTPUT:[0-9]*]] = "tf.B"(%[[RECV_OUTPUT]])
    // CHECK:            "tf._XlaSendFromHost"(%[[B_OUTPUT]], %[[PROGRAM_OUTPUT]])
    // CHECK-SAME:       key = "host_compute_channel_cluster1_retvals"
    // CHECK:          "tf_device.cluster"
    // CHECK:            %[[A_OUTPUT:[0-9]*]] = "tf.A"
    // CHECK:            %[[HOST_OUTPUT:[0-9]*]] = "tf._XlaHostComputeMlir"(%[[A_OUTPUT]])
    // CHECK-SAME:       recv_key = "host_compute_channel_cluster1_retvals"
    // CHECK:            "tf.C"(%[[HOST_OUTPUT]])
    %1:2 = tf_device.replicate([%0, %arg0] as %ri_0: tensor<?xi32>) {n = 2 : i32} {
      %2 = "tf_device.cluster"() ( {
        %3 = "tf.A"() : () -> (tensor<?xi32>)
        %4 = "tf.B"(%3) {_xla_outside_compilation = "cluster1"} : (tensor<?xi32>) -> (tensor<?xi32>)
        %5 = "tf.C"(%4) : (tensor<?xi32>) -> tensor<?xi32>
        tf_device.return %5 : tensor<?xi32>
      }) {num_cores_per_replica = 1, topology =  "", device_assignment =  []} : () -> tensor<?xi32>
      tf_device.return %2 : tensor<?xi32>
    }

    return %1 : tensor<?xi32>
  }

  // Tests extraction of a single outside compiled cluster with multiple input/output.

  // CHECK-LABEL: func @multiple_outside_compiled_input_output_single_outside_compilation
  func @multiple_outside_compiled_input_output_single_outside_compilation(%arg0: tensor<?xi32>) -> tensor<?xi32> {
    %0 = "tf.A"(%arg0) : (tensor<?xi32>) -> tensor<?xi32>
    // CHECK:      %[[REPLICATE:[0-9]*]]:2 = tf_device.replicate
    // CHECK:        %[[PARALLEL_EXECUTE_OUTPUT:[0-9]*]] = "tf_device.parallel_execute"
    // CHECK-NEXT:     "tf_device.launch"
    // CHECK:            %[[PROGRAM_OUTPUT:[a-z_0-9]*]] = "tf._TPUCompileMlirPlaceholderProgramKey"
    // CHECK:            %[[RECV_OUTPUT:[0-9]*]]:2 = "tf._XlaRecvAtHost"(%[[PROGRAM_OUTPUT]])
    // CHECK:            %[[B_OUTPUT:[0-9]*]]:2 = "tf.C"(%[[RECV_OUTPUT]]#0, %[[RECV_OUTPUT]]#1)
    // CHECK:            "tf._XlaSendFromHost"(%[[B_OUTPUT]]#0, %[[B_OUTPUT]]#1, %[[PROGRAM_OUTPUT]])
    // CHECK-SAME:       key = "host_compute_channel_cluster1_retvals"
    // CHECK:          "tf_device.cluster"
    // CHECK:            %[[A_OUTPUT:[0-9]*]] = "tf.A"
    // CHECK:            %[[B_OUTPUT:[0-9]*]] = "tf.B"
    // CHECK:            %[[HOST_OUTPUT:[0-9]*]]:2 = "tf._XlaHostComputeMlir"(%[[A_OUTPUT]], %[[B_OUTPUT]])
    // CHECK-SAME:       recv_key = "host_compute_channel_cluster1_retvals"
    // CHECK:            "tf.D"(%[[HOST_OUTPUT]]#0)
    // CHECK:            "tf.E"(%[[HOST_OUTPUT]]#1)
    %1:2 = tf_device.replicate([%0, %arg0] as %ri_0: tensor<?xi32>) {n = 2 : i32} {
      %2 = "tf_device.cluster"() ( {
        %3 = "tf.A"() : () -> (tensor<?xi32>)
        %4 = "tf.B"() : () -> (tensor<?xi32>)
        %5, %6 = "tf.C"(%3, %4) {_xla_outside_compilation = "cluster1"} : (tensor<?xi32>, tensor<?xi32>) -> (tensor<?xi32>, tensor<?xi32>)
        %7 = "tf.D"(%5) : (tensor<?xi32>) -> tensor<?xi32>
        %8 = "tf.E"(%6) : (tensor<?xi32>) -> tensor<?xi32>
        tf_device.return %8 : tensor<?xi32>
      }) {num_cores_per_replica = 1, topology =  "", device_assignment =  []} : () -> tensor<?xi32>
      tf_device.return %2 : tensor<?xi32>
    }

    return %1 : tensor<?xi32>
  }

  // Tests extraction of a multiple outside compiled clusters with input/output.

  // CHECK-LABEL: func @outside_compiled_input_output_multiple_outside_compilation
  func @outside_compiled_input_output_multiple_outside_compilation(%arg0: tensor<?xi32>) -> tensor<?xi32> {
    %0 = "tf.A"(%arg0) : (tensor<?xi32>) -> tensor<?xi32>
    // CHECK:      %[[REPLICATE:[0-9]*]]:2 = tf_device.replicate
    // CHECK:        %[[PARALLEL_EXECUTE_OUTPUT:[0-9]*]] = "tf_device.parallel_execute"
    // CHECK-NEXT:     "tf_device.launch"
    // CHECK:            %[[PROGRAM_OUTPUT2:[a-z_0-9]*]] = "tf._TPUCompileMlirPlaceholderProgramKey"
    // CHECK:            %[[RECV_OUTPUT2:[0-9]*]] = "tf._XlaRecvAtHost"(%[[PROGRAM_OUTPUT2]])
    // CHECK:            %[[D_OUTPUT:[0-9]*]] = "tf.D"(%[[RECV_OUTPUT2]])
    // CHECK:            "tf._XlaSendFromHost"(%[[D_OUTPUT]], %[[PROGRAM_OUTPUT]])
    // CHECK-SAME:       key = "host_compute_channel_cluster2_retvals"
    // CHECK:          "tf_device.launch"
    // CHECK:            %[[PROGRAM_OUTPUT1:[a-z_0-9]*]] = "tf._TPUCompileMlirPlaceholderProgramKey"
    // CHECK:            %[[RECV_OUTPUT1:[0-9]*]] = "tf._XlaRecvAtHost"(%[[PROGRAM_OUTPUT1]])
    // CHECK:            %[[B_OUTPUT:[0-9]*]] = "tf.B"(%[[RECV_OUTPUT1]])
    // CHECK:            "tf._XlaSendFromHost"(%[[B_OUTPUT]], %[[PROGRAM_OUTPUT]])
    // CHECK-SAME:       key = "host_compute_channel_cluster1_retvals"
    // CHECK:          "tf_device.cluster"
    // CHECK:            %[[A_OUTPUT:[0-9]*]] = "tf.A"
    // CHECK:            %[[HOST_OUTPUT1:[0-9]*]] = "tf._XlaHostComputeMlir"(%[[A_OUTPUT]])
    // CHECK-SAME:       recv_key = "host_compute_channel_cluster1_retvals"
    // CHECK:            %[[C_OUTPUT:[0-9]*]] = "tf.C"(%[[HOST_OUTPUT1]])
    // CHECK:            %[[HOST_OUTPUT2:[0-9]*]] = "tf._XlaHostComputeMlir"(%[[C_OUTPUT]])
    // CHECK-SAME:       recv_key = "host_compute_channel_cluster2_retvals"
    // CHECK:            "tf.E"(%[[HOST_OUTPUT2]])
    %1:2 = tf_device.replicate([%0, %arg0] as %ri_0: tensor<?xi32>) {n = 2 : i32} {
      %2 = "tf_device.cluster"() ( {
        %3 = "tf.A"() : () -> (tensor<?xi32>)
        %4 = "tf.B"(%3) {_xla_outside_compilation = "cluster1"} : (tensor<?xi32>) -> (tensor<?xi32>)
        %5 = "tf.C"(%4) : (tensor<?xi32>) -> (tensor<?xi32>)
        %6 = "tf.D"(%5) {_xla_outside_compilation = "cluster2"} : (tensor<?xi32>) -> (tensor<?xi32>)
        %7 = "tf.E"(%6) : (tensor<?xi32>) -> tensor<?xi32>
        tf_device.return %7 : tensor<?xi32>
      }) {num_cores_per_replica = 1, topology =  "", device_assignment =  []} : () -> tensor<?xi32>
      tf_device.return %2 : tensor<?xi32>
    }

    return %1 : tensor<?xi32>
  }

  // Tests extraction of a single outside compiled cluster with arg input and single device->host input.

  // CHECK-LABEL: func @mixed_input_single_outside_compilation
  func @mixed_input_single_outside_compilation(%arg0: tensor<?xi32>) -> tensor<?xi32> {
    %0 = "tf.A"(%arg0) : (tensor<?xi32>) -> tensor<?xi32>
    // CHECK:      %[[REPLICATE:[0-9]*]]:2 = tf_device.replicate
    // CHECK:        %[[PARALLEL_EXECUTE_OUTPUT:[0-9]*]] = "tf_device.parallel_execute"
    // CHECK-NEXT:     "tf_device.launch"
    // CHECK:            %[[PROGRAM_OUTPUT:[a-z_0-9]*]] = "tf._TPUCompileMlirPlaceholderProgramKey"
    // CHECK:            %[[RECV_OUTPUT:[0-9]*]] = "tf._XlaRecvAtHost"(%[[PROGRAM_OUTPUT]])
    // CHECK-SAME:       key = "host_compute_channel_cluster1_args"
    // CHECK:            "tf.B"(%arg0, %[[RECV_OUTPUT]])
    // CHECK:          "tf_device.cluster"
    // CHECK:            %[[A_OUTPUT:[0-9]*]] = "tf.A"
    // CHECK:            "tf._XlaHostComputeMlir"(%[[A_OUTPUT]])
    // CHECK-SAME:       send_key = "host_compute_channel_cluster1_args"
    %1:2 = tf_device.replicate([%0, %arg0] as %ri_0: tensor<?xi32>) {n = 2 : i32} {
      %2 = "tf_device.cluster"() ( {
        %3 = "tf.A"() : () -> (tensor<?xi32>)
        "tf.B"(%arg0, %3) {_xla_outside_compilation = "cluster1"} : (tensor<?xi32>, tensor<?xi32>) -> ()
        %4 = "tf.C"() : () -> tensor<?xi32>
        tf_device.return %4 : tensor<?xi32>
      }) {num_cores_per_replica = 1, topology =  "", device_assignment =  []} : () -> tensor<?xi32>
      tf_device.return %2 : tensor<?xi32>
    }

    return %1 : tensor<?xi32>
  }

  // Tests extraction of a multiple outside compiled clusters with single device->host input.

  // CHECK-LABEL: func @single_outside_compiled_input_multiple_outside_compilation
  func @single_outside_compiled_input_multiple_outside_compilation(%arg0: tensor<?xi32>) -> tensor<?xi32> {
    %0 = "tf.A"(%arg0) : (tensor<?xi32>) -> tensor<?xi32>
    // CHECK:      %[[REPLICATE:[0-9]*]]:2 = tf_device.replicate
    // CHECK:        %[[PARALLEL_EXECUTE_OUTPUT:[0-9]*]] = "tf_device.parallel_execute"
    // CHECK-NEXT:     "tf_device.launch"
    // CHECK:            %[[PROGRAM_OUTPUT_2:[a-z_0-9]*]] = "tf._TPUCompileMlirPlaceholderProgramKey"
    // CHECK:            %[[RECV_OUTPUT_2:[0-9]*]] = "tf._XlaRecvAtHost"(%[[PROGRAM_OUTPUT_2]])
    // CHECK-SAME:      key = "host_compute_channel_cluster2_args"
    // CHECK:           "tf.D"(%[[RECV_OUTPUT_2]])
    // CHECK:          "tf_device.launch"
    // CHECK:            %[[PROGRAM_OUTPUT_1:[a-z_0-9]*]] = "tf._TPUCompileMlirPlaceholderProgramKey"
    // CHECK:            %[[RECV_OUTPUT_1:[0-9]*]] = "tf._XlaRecvAtHost"(%[[PROGRAM_OUTPUT_1]])
    // CHECK-SAME:       key = "host_compute_channel_cluster1_args"
    // CHECK:            "tf.B"(%[[RECV_OUTPUT_1]])
    // CHECK:          "tf_device.cluster"
    // CHECK:            %[[A_OUTPUT:[0-9]*]] = "tf.A"
    // CHECK:            "tf._XlaHostComputeMlir"(%[[A_OUTPUT]])
    // CHECK-SAME:       send_key = "host_compute_channel_cluster1_args"
    // CHECK:            %[[C_OUTPUT:[0-9]*]] = "tf.C"
    // CHECK:            "tf._XlaHostComputeMlir"(%[[C_OUTPUT]])
    // CHECK-SAME:       send_key = "host_compute_channel_cluster2_args"
    %1:2 = tf_device.replicate([%0, %arg0] as %ri_0: tensor<?xi32>) {n = 2 : i32} {
      %2 = "tf_device.cluster"() ( {
        %3 = "tf.A"() : () -> (tensor<?xi32>)
        "tf.B"(%3) {_xla_outside_compilation = "cluster1"} : (tensor<?xi32>) -> ()
        %4 = "tf.C"() : () -> tensor<?xi32>
        "tf.D"(%4) {_xla_outside_compilation = "cluster2"} : (tensor<?xi32>) -> ()
        tf_device.return %4 : tensor<?xi32>
      }) {num_cores_per_replica = 1, topology =  "", device_assignment =  []} : () -> tensor<?xi32>
      tf_device.return %2 : tensor<?xi32>
    }

    return %1 : tensor<?xi32>
  }

  // Tests extraction of a single outside compiled cluster with multiple device->host inputs.

  // CHECK-LABEL: func @multiple_outside_compiled_inputs_single_outside_compilation
  func @multiple_outside_compiled_inputs_single_outside_compilation(%arg0: tensor<?xi32>) -> tensor<?xi32> {
    %0 = "tf.A"(%arg0) : (tensor<?xi32>) -> tensor<?xi32>
    // CHECK:      %[[REPLICATE:[0-9]*]]:2 = tf_device.replicate
    // CHECK:        %[[PARALLEL_EXECUTE_OUTPUT:[0-9]*]] = "tf_device.parallel_execute"
    // CHECK-NEXT:     "tf_device.launch"
    // CHECK:            %[[PROGRAM_OUTPUT:[a-z_0-9]*]] = "tf._TPUCompileMlirPlaceholderProgramKey"
    // CHECK:            %[[RECV_OUTPUT:[0-9]*]]:2 = "tf._XlaRecvAtHost"(%[[PROGRAM_OUTPUT]])
    // CHECK-SAME:       key = "host_compute_channel_cluster1_args"
    // CHECK:            "tf.C"(%[[RECV_OUTPUT]]#0)
    // CHECK:            "tf.D"(%[[RECV_OUTPUT]]#1, %[[RECV_OUTPUT]]#0)
    // CHECK:          "tf_device.cluster"
    // CHECK:            %[[A_OUTPUT:[0-9]*]] = "tf.A"
    // CHECK:            %[[B_OUTPUT:[0-9]*]] = "tf.B"
    // CHECK:            "tf._XlaHostComputeMlir"(%[[A_OUTPUT]], %[[B_OUTPUT]])
    // CHECK-SAME:       send_key = "host_compute_channel_cluster1_args"
    %1:2 = tf_device.replicate([%0, %arg0] as %ri_0: tensor<?xi32>) {n = 2 : i32} {
      %2 = "tf_device.cluster"() ( {
        %3 = "tf.A"() : () -> (tensor<?xi32>)
        %4 = "tf.B"() : () -> (tensor<?xi32>)
        "tf.C"(%3) {_xla_outside_compilation = "cluster1"} : (tensor<?xi32>) -> ()
        "tf.D"(%4, %3) {_xla_outside_compilation = "cluster1"} : (tensor<?xi32>, tensor<?xi32>) -> ()
        %5 = "tf.E"() : () -> tensor<?xi32>
        tf_device.return %5 : tensor<?xi32>
      }) {num_cores_per_replica = 1, topology =  "", device_assignment =  []} : () -> tensor<?xi32>
      tf_device.return %2 : tensor<?xi32>
    }

    return %1 : tensor<?xi32>
  }

  // Tests only directly used results of tpu cluster are remapped with
  // parallel_execute.

  // CHECK-LABEL: func @remapped_results
  func @remapped_results(%arg0: tensor<?xi32>) -> tensor<?xi32> {
    %0 = "tf.A"(%arg0) : (tensor<?xi32>) -> tensor<?xi32>
    // CHECK: %[[REPLICATE:[0-9]*]]:2 = tf_device.replicate
    // CHECK:   %[[PARALLEL_EXECUTE_OUTPUT:[0-9]*]]:2 = "tf_device.parallel_execute"
    // CHECK: tf_device.return %[[PARALLEL_EXECUTE_OUTPUT]]#1 : tensor<?xi32>
    %1:2 = tf_device.replicate([%0, %arg0] as %ri_0: tensor<?xi32>) {n = 2 : i32} {
      %2:2 = "tf_device.cluster"() ( {
        %3 = "tf.A"() : () -> (tensor<?xi32>)
        %4 = "tf.B"(%3) {_xla_outside_compilation = "cluster1"} : (tensor<?xi32>) -> (tensor<?xi32>)
        %5:2 = "tf.C"(%4) : (tensor<?xi32>) -> (tensor<?xi32>, tensor<?xi32>)
        tf_device.return %5#0, %5#1 : tensor<?xi32>, tensor<?xi32>
      }) {num_cores_per_replica = 1, topology =  "", device_assignment =  []} : () -> (tensor<?xi32>, tensor<?xi32>)
      tf_device.return %2#1 : tensor<?xi32>
    }
    return %1 : tensor<?xi32>
  }

  // Tests extraction of a single outside compiled cluster inside a tf.IfRegion op.

  // CHECK-LABEL: func @outside_compiled_ops_inside_tf_if
  func @outside_compiled_ops_inside_tf_if(%arg0: tensor<?xi32>) -> tensor<?xi32> {
    %0 = "tf.A"(%arg0) : (tensor<?xi32>) -> tensor<?xi32>

    // CHECK:      %[[REPLICATE:[0-9]*]]:2 = tf_device.replicate
    // CHECK:        %[[PARALLEL_EXECUTE_OUTPUT:[0-9]*]] = "tf_device.parallel_execute"
    // CHECK-NEXT:     "tf_device.launch"
    // CHECK-NEXT:      %[[PLACEHOLDER_KEY:[0-9]*]] = "tf._TPUCompileMlirPlaceholderProgramKey"()
    // CHECK-NEXT:      %[[PREDICATE_RECV_OUTPUT:[0-9]*]] = "tf._XlaRecvAtHost"(%[[PLACEHOLDER_KEY]])
    // CHECK-SAME:      device_ordinal = 0
    // CHECK-SAME:      key = "if_predicate_channel_cluster1_0"
    // CHECK-NEXT:       tf.IfRegion"(%[[PREDICATE_RECV_OUTPUT]])
    // CHECK-NEXT:         %[[ARG_RECV_OUTPUT:[0-9]*]]:2 = "tf._XlaRecvAtHost"(%[[PLACEHOLDER_KEY]])
    // CHECK-SAME:         device_ordinal = 0
    // CHECK-SAME:         key = "host_compute_channel_cluster1_args"
    // CHECK:              "tf.D"(%[[ARG_RECV_OUTPUT]]#0, %[[ARG_RECV_OUTPUT]]#1)
    // CHECK:              "tf._XlaSendFromHost"(%[[PLACEHOLDER_KEY]])
    // CHECK-SAME:         device_ordinal = 0
    // CHECK-SAME:         key = "host_compute_channel_cluster1_retvals"
    // CHECK-NEXT:         "tf.Yield"() : () -> ()
    // CHECK:          "tf_device.cluster"
    // CHECK:            %[[A_OUTPUT:[0-9]*]] = "tf.A"
    // CHECK:            %[[B_OUTPUT:[0-9]*]] = "tf.B"
    // CHECK:            %[[G_OUTPUT:[0-9]*]] = "tf.G"
    // CHECK:            "tf.XlaSendToHost"(%6) {key = "if_predicate_channel_cluster1_0"}
    // CHECK-NEXT:       tf.IfRegion"(%[[G_OUTPUT]])
    // CHECK:              "tf._XlaHostComputeMlir"(%[[B_OUTPUT]], %[[A_OUTPUT]])
    // CHECK-SAME:         recv_key = "host_compute_channel_cluster1_retvals"
    // CHECK-SAME:         send_key = "host_compute_channel_cluster1_args"
    // CHECK-SAME:         tpu_core = 0
    // CHECK-NEXT:         "tf.Yield"() : () -> ()
    %1:2 = tf_device.replicate([%0, %arg0] as %ri_0: tensor<?xi32>) {n = 2 : i32} {
      %2 = "tf_device.cluster"() ( {
        %3 = "tf.A"() : () -> (tensor<?xi32>)
        %4 = "tf.B"() : () -> (tensor<?xi32>)
        %6 = "tf.G"() : () -> (tensor<i1>)

        "tf.IfRegion"(%6) ({
          "tf.D"(%4, %3) {_xla_outside_compilation = "cluster1"} : (tensor<?xi32>, tensor<?xi32>) -> ()
          "tf.Yield"() : () -> ()
        }, {
          "tf.Yield"() : () -> ()
        }) { is_stateless = false} : (tensor<i1>) -> ()

        %5 = "tf.E"() : () -> tensor<?xi32>
        tf_device.return %5 : tensor<?xi32>
      }) {num_cores_per_replica = 1, topology =  "", device_assignment =  []} : () -> tensor<?xi32>
      tf_device.return %2 : tensor<?xi32>
    }

    return %1 : tensor<?xi32>
  }

  // Tests extraction of a single outside compiled cluster inside a tf.IfRegion
  // op with return values.

  // CHECK-LABEL: func @outside_compiled_ops_inside_tf_if_with_return_values
  func @outside_compiled_ops_inside_tf_if_with_return_values(
    %arg0: tensor<?xi32>) -> tensor<?xi32> {
    %0 = "tf.A"(%arg0) : (tensor<?xi32>) -> tensor<?xi32>

    // CHECK:      %[[REPLICATE:[0-9]*]]:2 = tf_device.replicate
    // CHECK:        %[[PARALLEL_EXECUTE_OUTPUT:[0-9]*]] = "tf_device.parallel_execute"
    // CHECK-NEXT:     "tf_device.launch"
    // CHECK-NEXT:      %[[PLACEHOLDER_KEY:[0-9]*]] = "tf._TPUCompileMlirPlaceholderProgramKey"()
    // CHECK-NEXT:      %[[PREDICATE_RECV_OUTPUT:[0-9]*]] = "tf._XlaRecvAtHost"(%[[PLACEHOLDER_KEY]])
    // CHECK-SAME:      device_ordinal = 0
    // CHECK-SAME:      key = "if_predicate_channel_cluster1_0"
    // CHECK-NEXT:       tf.IfRegion"(%[[PREDICATE_RECV_OUTPUT]])
    // CHECK-NEXT:         %[[ARG_RECV_OUTPUT:[0-9]*]]:2 = "tf._XlaRecvAtHost"(%[[PLACEHOLDER_KEY]])
    // CHECK-SAME:         device_ordinal = 0
    // CHECK-SAME:         key = "host_compute_channel_cluster1_args"
    // CHECK:              %[[D_OUTPUT:[0-9]*]] = "tf.D"(%[[ARG_RECV_OUTPUT]]#0, %[[ARG_RECV_OUTPUT]]#1)
    // CHECK:              "tf._XlaSendFromHost"(%[[D_OUTPUT]], %[[PLACEHOLDER_KEY]])
    // CHECK-SAME:         device_ordinal = 0
    // CHECK-SAME:         key = "host_compute_channel_cluster1_retvals"
    // CHECK-NEXT:         "tf.Yield"() : () -> ()
    // CHECK:          "tf_device.cluster"
    // CHECK:            %[[A_OUTPUT:[0-9]*]] = "tf.A"
    // CHECK:            %[[B_OUTPUT:[0-9]*]] = "tf.B"
    // CHECK:            %[[G_OUTPUT:[0-9]*]] = "tf.G"
    // CHECK:            "tf.XlaSendToHost"(%6) {key = "if_predicate_channel_cluster1_0"}
    // CHECK-NEXT:       tf.IfRegion"(%[[G_OUTPUT]])
    // CHECK:              %[[HOST_COMPUTE_OUT:[0-9]*]] = "tf._XlaHostComputeMlir"(%[[B_OUTPUT]], %[[A_OUTPUT]])
    // CHECK-SAME:         recv_key = "host_compute_channel_cluster1_retvals"
    // CHECK-SAME:         send_key = "host_compute_channel_cluster1_args"
    // CHECK-SAME:         tpu_core = 0
    // CHECK-NEXT:         "tf.Yield"(%[[HOST_COMPUTE_OUT]])
    %1:2 = tf_device.replicate([%0, %arg0] as %ri_0: tensor<?xi32>) {n = 2 : i32} {
      %2 = "tf_device.cluster"() ( {
        %3 = "tf.A"() : () -> (tensor<?xi32>)
        %4 = "tf.B"() : () -> (tensor<?xi32>)
        %6 = "tf.G"() : () -> (tensor<i1>)

        "tf.IfRegion"(%6) ({
          %7 = "tf.D"(%4, %3) {_xla_outside_compilation = "cluster1"} : (tensor<?xi32>, tensor<?xi32>) -> (tensor<?xi32>)
          "tf.Yield"(%7) : (tensor<?xi32>) -> ()
        }, {

          %8 = "tf.F"() : () -> (tensor<?xi32>)
          "tf.Yield"(%8) : (tensor<?xi32>) -> ()
        }) { is_stateless = false} : (tensor<i1>) -> (tensor<?xi32>)

        %5 = "tf.E"() : () -> tensor<?xi32>
        tf_device.return %5 : tensor<?xi32>
      }) {num_cores_per_replica = 1, topology =  "", device_assignment =  []} : () -> tensor<?xi32>
      tf_device.return %2 : tensor<?xi32>
    }

    return %1 : tensor<?xi32>
  }

  // Tests extraction of a single outside compiled cluster inside a tf.IfRegion op without external inputs/outputs

  // CHECK-LABEL: func @outside_compiled_ops_inside_tf_if_without_input_outputs
  func @outside_compiled_ops_inside_tf_if_without_input_outputs(
    %arg0: tensor<?xi32>) -> tensor<?xi32> {
    %0 = "tf.A"(%arg0) : (tensor<?xi32>) -> tensor<?xi32>
    // CHECK:      %[[REPLICATE:[0-9]*]]:2 = tf_device.replicate
    // CHECK:        %[[PARALLEL_EXECUTE_OUTPUT:[0-9]*]] = "tf_device.parallel_execute"
    // CHECK-NEXT:     "tf_device.launch"
    // CHECK-NEXT:      %[[PLACEHOLDER_KEY:[0-9]*]] = "tf._TPUCompileMlirPlaceholderProgramKey"()
    // CHECK-NEXT:      %[[PREDICATE_RECV_OUTPUT:[0-9]*]] = "tf._XlaRecvAtHost"(%[[PLACEHOLDER_KEY]])
    // CHECK-SAME:      device_ordinal = 0
    // CHECK-SAME:      key = "if_predicate_channel_cluster1_0"
    // CHECK-NEXT:       tf.IfRegion"(%[[PREDICATE_RECV_OUTPUT]])
    // CHECK:              "tf.D"
    // CHECK-NEXT:         "tf.Yield"() : () -> ()
    // CHECK:          "tf_device.cluster"
    // CHECK:            %[[A_OUTPUT:[0-9]*]] = "tf.A"
    // CHECK:            %[[B_OUTPUT:[0-9]*]] = "tf.B"
    // CHECK:            %[[G_OUTPUT:[0-9]*]] = "tf.G"
    // CHECK:            "tf.XlaSendToHost"(%6) {key = "if_predicate_channel_cluster1_0"}
    // CHECK-NEXT:       tf.IfRegion"(%[[G_OUTPUT]])
    // CHECK-NEXT:         "tf.Yield"() : () -> ()
    %1:2 = tf_device.replicate([%0, %arg0] as %ri_0: tensor<?xi32>) {n = 2 : i32} {
      %2 = "tf_device.cluster"() ( {
        %3 = "tf.A"() : () -> (tensor<?xi32>)
        %4 = "tf.B"() : () -> (tensor<?xi32>)
        %6 = "tf.G"() : () -> (tensor<i1>)

        "tf.IfRegion"(%6) ({
          "tf.D"() {_xla_outside_compilation = "cluster1"} : () -> ()
          "tf.Yield"() : () -> ()
        }, {
          "tf.Yield"() : () -> ()
        }) { is_stateless = false} : (tensor<i1>) -> ()

        %5 = "tf.E"() : () -> tensor<?xi32>
        tf_device.return %5 : tensor<?xi32>
      }) {num_cores_per_replica = 1, topology =  "", device_assignment =  []} : () -> tensor<?xi32>
      tf_device.return %2 : tensor<?xi32>
    }

    return %1 : tensor<?xi32>
  }

  // Tests extraction of a single outside compiled cluster inside a nested
  // tf.IfRegion op.

  // CHECK-LABEL: func @outside_compiled_ops_inside_nested_if
  func @outside_compiled_ops_inside_nested_if(%arg0: tensor<?xi32>) -> tensor<?xi32> {
    %0 = "tf.A"(%arg0) : (tensor<?xi32>) -> tensor<?xi32>
    // CHECK:      %[[REPLICATE:[0-9]*]]:2 = tf_device.replicate
    // CHECK:        %[[PARALLEL_EXECUTE_OUTPUT:[0-9]*]] = "tf_device.parallel_execute"
    // CHECK-NEXT:     "tf_device.launch"
    // CHECK-NEXT:      %[[PLACEHOLDER_KEY:[0-9]*]] = "tf._TPUCompileMlirPlaceholderProgramKey"()
    // CHECK-NEXT:      %[[PREDICATE_RECV_OUTPUT:[0-9]*]] = "tf._XlaRecvAtHost"(%[[PLACEHOLDER_KEY]])
    // CHECK-SAME:      device_ordinal = 0
    // CHECK-SAME:      key = "if_predicate_channel_cluster1_0"
    // CHECK-NEXT:      tf.IfRegion"(%[[PREDICATE_RECV_OUTPUT]])
    // CHECK-NEXT:        %[[PREDICATE2_RECV_OUTPUT:[0-9]*]] = "tf._XlaRecvAtHost"(%[[PLACEHOLDER_KEY]])
    // CHECK-SAME:        device_ordinal = 0
    // CHECK-SAME:        key = "if_predicate_channel_cluster1_1"
    // CHECK-NEXT:        tf.IfRegion"(%[[PREDICATE2_RECV_OUTPUT]])
    // CHECK-NEXT:          "tf.Yield"() : () -> ()
    // CHECK:               %[[ARG_RECV_OUTPUT:[0-9]*]] = "tf._XlaRecvAtHost"(%[[PLACEHOLDER_KEY]])
    // CHECK-SAME:          device_ordinal = 0
    // CHECK-SAME:          key = "host_compute_channel_cluster1_args"
    // CHECK:               "tf.D"(%[[ARG_RECV_OUTPUT]])
    // CHECK:               "tf._XlaSendFromHost"(%[[PLACEHOLDER_KEY]])
    // CHECK-SAME:          device_ordinal = 0
    // CHECK-SAME:          key = "host_compute_channel_cluster1_retvals"
    // CHECK-NEXT:          "tf.Yield"() : () -> ()

    // CHECK:          "tf_device.cluster"
    // CHECK:            %[[A_OUTPUT:[0-9]*]] = "tf.A"
    // CHECK:            %[[B_OUTPUT:[0-9]*]] = "tf.B"
    // CHECK:            %[[G_OUTPUT:[0-9]*]] = "tf.G"
    // CHECK:            "tf.XlaSendToHost"(%[[G_OUTPUT]]) {key = "if_predicate_channel_cluster1_0"}
    // CHECK-NEXT:       tf.IfRegion"(%[[G_OUTPUT]])
    // CHECK:              %[[H_OUTPUT:[0-9]*]] = "tf.H"(%[[B_OUTPUT]])
    // CHECK:              "tf.XlaSendToHost"(%[[H_OUTPUT]]) {key = "if_predicate_channel_cluster1_1"}
    // CHECK-NEXT:         tf.IfRegion"(%[[H_OUTPUT]])
    // CHECK-NEXT:           "tf.Yield"() : () -> ()
    // CHECK:                 %[[I_OUTPUT:[0-9]*]] = "tf.I"(%[[H_OUTPUT]])
    // CHECK:                 "tf._XlaHostComputeMlir"(%[[I_OUTPUT]])
    // CHECK-NEXT:            "tf.Yield"() : () -> ()
    %1:2 = tf_device.replicate([%0, %arg0] as %ri_0: tensor<?xi32>) {n = 2 : i32} {
      %2 = "tf_device.cluster"() ( {
        %3 = "tf.A"() : () -> (tensor<?xi32>)
        %4 = "tf.B"() : () -> (tensor<?xi32>)
        %6 = "tf.G"() : () -> (tensor<i1>)

        "tf.IfRegion"(%6) ({
           %7 = "tf.H"(%4) : (tensor<?xi32>) -> (tensor<i1>)

          "tf.IfRegion"(%7)({
              "tf.Yield"() : () -> ()
            },
            {
              %8 = "tf.I"(%7) : (tensor<i1>) -> (tensor<?xi32>)
              "tf.D"(%8) {_xla_outside_compilation = "cluster1"} : (tensor<?xi32>) -> ()
              "tf.Yield"() : () -> ()
            }) { is_stateless = false} : (tensor<i1>) -> ()

          "tf.Yield"() : () -> ()
        }, {
          "tf.Yield"() : () -> ()
        }) { is_stateless = false} : (tensor<i1>) -> ()

        %5 = "tf.E"() : () -> tensor<?xi32>
        tf_device.return %5 : tensor<?xi32>
      }) {num_cores_per_replica = 1, topology =  "", device_assignment =  []} : () -> tensor<?xi32>
      tf_device.return %2 : tensor<?xi32>
    }

    return %1 : tensor<?xi32>
  }
}
