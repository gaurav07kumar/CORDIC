`timescale 1ns/1ps

module cordic_tb;

  // ----------------------------------------------------------
  // Parameters 
  // ----------------------------------------------------------
  parameter width = 16;
  parameter N = 32;

  // ----------------------------------------------------------
  // DUT Signals
  // ----------------------------------------------------------
  reg clk;
  reg rst;
  reg valid_in;
  reg signed [N-1:0] angle;

  wire signed [width-1:0] cosine;
  wire signed [width-1:0] sine;
  wire valid_out;

  // ----------------------------------------------------------
  // Instantiate DUT
  // ----------------------------------------------------------
  CORDIC dut (
    .clk(clk),
    .rst(rst),
    .valid_in(valid_in),
    .angle(angle),
    .cosine(cosine),
    .sine(sine),
    .valid_out(valid_out)
  );

  // ----------------------------------------------------------
  // Clock Generation (100 MHz)
  // ----------------------------------------------------------
  always #5 clk = ~clk;

  // ----------------------------------------------------------
  // Testbench Variables
  // ----------------------------------------------------------
  integer i;
  real deg;
  real exp_cos, exp_sin, got_cos, got_sin, err_cos, err_sin;
  
  real PI = 3.14159265358979323846;
  real SCALE = 32767.0;

  // Queue to track which degree corresponds to the current output
  // Expanded to handle thousands of random tests
  real deg_queue [0:5000]; 
  integer push_idx = 0;
  integer pop_idx  = 0;

  function real rabs(input real v);
    begin
      rabs = (v >= 0.0) ? v : -v;
    end
  endfunction

  // ----------------------------------------------------------
  // Main Stimulus Block (Feeding the Pipeline)
  // ----------------------------------------------------------
  initial begin
    $dumpfile("cordic_tb.vcd");
    $dumpvars(0, cordic_tb);

    // 1. Initial State & Power-on Reset
    clk = 0;
    rst = 1;
    valid_in = 0;
    angle = 0;
    repeat(3) @(negedge clk);
    rst = 0;

    // ========================================================
    // TEST PHASE 0: The "Garbage" Injection
    // Goal: Cover the 'default' case by forcing Unknowns (X)
    // ========================================================
    $display("Starting Phase 0: Injecting Unknowns (X)...");
    @(negedge clk);
    valid_in = 1;
    angle = 32'hXXXX_XXXX; // Force the quadrant wire to become 2'bXX
    @(negedge clk);
    valid_in = 0;
    // Wait for the pipeline to clear the garbage
    repeat(20) @(posedge clk);

    
    // ========================================================
    // TEST PHASE 1: Sequential Sweep (0 to 360)
    // Goal: Statement and Block Coverage
    // ========================================================
    $display("Starting Phase 1: 0 to 360 Sweep...");
    for (i = 0; i <= 360; i = i + 1) begin
      @(negedge clk);
      deg = i * 1.0;
      angle = $rtoi((deg / 360.0) * 4294967296.0);
      valid_in = 1;
      deg_queue[push_idx] = deg;
      push_idx = push_idx + 1;
    end

    // ========================================================
    // TEST PHASE 2: Pipeline Bubbles & Randomized Data
    // Goal: Toggle Coverage & Control Path Verification
    // ========================================================
    $display("Starting Phase 2: Random Angles & Pipeline Bubbles...");
    for (i = 0; i < 2000; i = i + 1) begin
      @(negedge clk);
      
      // Generate a completely random 32-bit angle
      angle = {$random, $random}; 
      
      // Back-calculate the degree for the monitor checking queue
      // Modulo arithmetic to keep it in a readable 0-360 range for the console
      deg = ($itor(angle) / 4294967296.0) * 360.0;
      if (deg < 0) deg = deg + 360.0; 

      // Randomly inject valid_in bubbles (approx 50% of the time data is invalid)
      valid_in = $random % 2; 

      // Only push to our checking queue if we actually asserted valid_in
      if (valid_in) begin
        deg_queue[push_idx] = deg;
        push_idx = push_idx + 1;
      end
    end

    // ========================================================
    // TEST PHASE 3: Mid-Flight Reset Assertion
    // Goal: Asynchronous/Synchronous Reset Path Coverage
    // ========================================================
    $display("Starting Phase 3: Mid-Flight Reset...");
    @(negedge clk);
    valid_in = 1;
    angle = 32'h40000000; // 90 degrees
    deg_queue[push_idx] = 90.0;
    push_idx = push_idx + 1;
    
    repeat(5) @(negedge clk); // Wait for data to get halfway through pipeline
    
    // Assert reset mid-calculation!
    rst = 1;
    valid_in = 0;
    repeat(2) @(negedge clk);
    rst = 0;
    
    // Note: Because we reset, the data currently in the pipeline is dead.
    // We must artificially advance our pop_idx so the monitor doesn't 
    // wait for an answer that will never arrive.
    pop_idx = push_idx; 

    // Flush the pipeline
    valid_in = 0;
    repeat(30) @(posedge clk);

    $display("============================================================");
    $display(" Simulation and Coverage Run Complete.");
    $display("============================================================");
    $finish;
  end

  // ----------------------------------------------------------
  // Output Monitor Block (Checking the Results)
  // ----------------------------------------------------------
  always @(posedge clk) begin
    if (valid_out && !rst) begin
      
      deg = deg_queue[pop_idx];
      pop_idx = pop_idx + 1;

      exp_cos = $cos(deg * PI / 180.0);
      exp_sin = $sin(deg * PI / 180.0);

      got_cos = $itor(cosine) / SCALE;
      got_sin = $itor(sine)   / SCALE;

      err_cos = rabs(got_cos - exp_cos);
      err_sin = rabs(got_sin - exp_sin);

      // Only print if there is a massive error, otherwise console gets flooded
      if (err_cos > 0.005 || err_sin > 0.005) begin
        $display("ERROR at Angle %3.1f° | Cos Err: %.4f | Sin Err: %.4f", deg, err_cos, err_sin);
      end
    end
  end

endmodule