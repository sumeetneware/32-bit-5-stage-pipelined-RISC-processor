
// =======================================================
// Testbench Step 8: Performance Metrics + Cache Stats
// =======================================================
module tb_pipelined_cpu_step8;
    reg clk;
    reg reset;
    wire [31:0] pc_out;
    wire [31:0] instruction_out;

    integer fail_count;
    real cpi;
    real i_hit_rate;
    real d_hit_rate;

    pipelined_cpu dut (
        .clk(clk),
        .reset(reset),
        .pc_out(pc_out),
        .instruction_out(instruction_out)
    );

    always #5 clk = ~clk;

    task check_reg;
        input [4:0] reg_idx;
        input [31:0] expected;
        begin
            #1;
            if (dut.reg_file.reg_array[reg_idx] !== expected) begin
                fail_count = fail_count + 1;
                $display("FAIL REG x%0d | got=%h expected=%h",
                         reg_idx, dut.reg_file.reg_array[reg_idx], expected);
            end else begin
                $display("PASS REG x%0d | val=%h", reg_idx, expected);
            end
        end
    endtask

    task check_mem;
        input [7:0] word_idx;
        input [31:0] expected;
        begin
            #1;
            if (dut.dmem.mem[word_idx] !== expected) begin
                fail_count = fail_count + 1;
                $display("FAIL MEM[%0d] | got=%h expected=%h",
                         word_idx, dut.dmem.mem[word_idx], expected);
            end else begin
                $display("PASS MEM[%0d] | val=%h", word_idx, expected);
            end
        end
    endtask

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_pipelined_cpu_step8);
        $display("---- Pipelined CPU Step-8 Test Start ----");

        clk = 1'b0;
        reset = 1'b1;
        fail_count = 0;

        // Data init
        dut.dmem.mem[0]  = 32'd10;
        dut.dmem.mem[16] = 32'd40; // address 64, same D$ index as address 0

        // Program:
        // 0: lw  r1, 0(r0)      // D$ miss
        // 1: lw  r2, 0(r0)      // D$ hit
        // 2: lw  r3, 64(r0)     // D$ miss (conflict)
        // 3: lw  r4, 0(r0)      // D$ miss (conflict)
        // 4: add r5, r1, r4
        // 5: sw  r5, 8(r0)
        // 6: beq r0, r0, -1     // loop for I$ hit growth
        dut.imem.mem[0] = {6'b100011, 5'd0, 5'd1, 16'd0};
        dut.imem.mem[1] = {6'b100011, 5'd0, 5'd2, 16'd0};
        dut.imem.mem[2] = {6'b100011, 5'd0, 5'd3, 16'd64};
        dut.imem.mem[3] = {6'b100011, 5'd0, 5'd4, 16'd0};
        dut.imem.mem[4] = {6'b000000, 5'd1, 5'd4, 5'd5, 5'd0, 6'b100000};
        dut.imem.mem[5] = {6'b101011, 5'd0, 5'd5, 16'd8};
        dut.imem.mem[6] = {6'b000100, 5'd0, 5'd0, 16'hFFFF};

        repeat (2) @(posedge clk);
        reset = 1'b0;

        repeat (50) @(posedge clk);

        // Functional checks
        check_reg(5'd1, 32'd10);
        check_reg(5'd2, 32'd10);
        check_reg(5'd3, 32'd40);
        check_reg(5'd4, 32'd10);
        check_reg(5'd5, 32'd20);
        check_mem(8'd2, 32'd20);

        // Counter sanity
        if (dut.cycle_count == 0 || dut.instr_retired_count == 0) begin
            fail_count = fail_count + 1;
            $display("FAIL PERF counters | cycles=%0d retired=%0d",
                     dut.cycle_count, dut.instr_retired_count);
        end

        // Exact D$ expected for this sequence
        if (dut.dcache.access_count !== 32'd5 ||
            dut.dcache.hit_count    !== 32'd1 ||
            dut.dcache.miss_count   !== 32'd4) begin
            fail_count = fail_count + 1;
            $display("FAIL D$ counters | access=%0d hit=%0d miss=%0d | expected 5/1/4",
                     dut.dcache.access_count, dut.dcache.hit_count, dut.dcache.miss_count);
        end else begin
            $display("PASS D$ counters | access=%0d hit=%0d miss=%0d",
                     dut.dcache.access_count, dut.dcache.hit_count, dut.dcache.miss_count);
        end

        // I$ should have misses initially and hits during loop
        if (dut.icache.hit_count == 0 || dut.icache.miss_count == 0) begin
            fail_count = fail_count + 1;
            $display("FAIL I$ counters | access=%0d hit=%0d miss=%0d",
                     dut.icache.access_count, dut.icache.hit_count, dut.icache.miss_count);
        end else begin
            $display("PASS I$ counters | access=%0d hit=%0d miss=%0d",
                     dut.icache.access_count, dut.icache.hit_count, dut.icache.miss_count);
        end

        // Compute metrics
        cpi = (dut.instr_retired_count != 0) ?
              (dut.cycle_count * 1.0 / dut.instr_retired_count) : 0.0;

        i_hit_rate = (dut.icache.access_count != 0) ?
                     ((dut.icache.hit_count * 100.0) / dut.icache.access_count) : 0.0;

        d_hit_rate = (dut.dcache.access_count != 0) ?
                     ((dut.dcache.hit_count * 100.0) / dut.dcache.access_count) : 0.0;

        $display("----- Performance Report -----");
        $display("Total Cycles              : %0d", dut.cycle_count);
        $display("Instructions Retired      : %0d", dut.instr_retired_count);
        $display("CPI                       : %0f", cpi);
        $display("I-Cache Access/Hit/Miss   : %0d / %0d / %0d",
                 dut.icache.access_count, dut.icache.hit_count, dut.icache.miss_count);
        $display("I-Cache Hit Rate (%%)      : %0f", i_hit_rate);
        $display("D-Cache Access/Hit/Miss   : %0d / %0d / %0d",
                 dut.dcache.access_count, dut.dcache.hit_count, dut.dcache.miss_count);
        $display("D-Cache Hit Rate (%%)      : %0f", d_hit_rate);

        if (fail_count == 0) begin
            $display("ALL CHECKS PASSED");
        end else begin
            $display("TEST FAILED with %0d issue(s)", fail_count);
        end

        $display("Final PC = %h", pc_out);
        $display("---- Pipelined CPU Step-8 Test End ----");
        $finish;
    end
endmodule
