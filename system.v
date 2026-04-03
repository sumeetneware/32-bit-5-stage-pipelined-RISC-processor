`timescale 1ns/1ps

// =======================================================
// ALU
// =======================================================
module alu (
    input  wire [31:0] operand_a,
    input  wire [31:0] operand_b,
    input  wire [2:0]  alu_control,
    output reg  [31:0] alu_result,
    output wire        zero_flag
);
    always @(*) begin
        case (alu_control)
            3'b000: alu_result = operand_a + operand_b; // ADD
            3'b001: alu_result = operand_a - operand_b; // SUB
            3'b010: alu_result = operand_a & operand_b; // AND
            3'b011: alu_result = operand_a | operand_b; // OR
            default: alu_result = 32'd0;
        endcase
    end

    assign zero_flag = (alu_result == 32'd0);
endmodule

// =======================================================
// Register File (32x32) with same-cycle WB->ID bypass
// =======================================================
module register_file (
    input  wire        clk,
    input  wire        reset,
    input  wire        reg_write_en,
    input  wire [4:0]  read_addr1,
    input  wire [4:0]  read_addr2,
    input  wire [4:0]  write_addr,
    input  wire [31:0] write_data,
    output wire [31:0] read_data1,
    output wire [31:0] read_data2
);
    reg [31:0] reg_array [0:31];
    integer i;

    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < 32; i = i + 1) begin
                reg_array[i] <= 32'd0;
            end
        end else if (reg_write_en && (write_addr != 5'd0)) begin
            reg_array[write_addr] <= write_data;
        end
    end

    assign read_data1 = (read_addr1 == 5'd0) ? 32'd0 :
                        ((reg_write_en && (write_addr != 5'd0) && (write_addr == read_addr1)) ?
                         write_data : reg_array[read_addr1]);

    assign read_data2 = (read_addr2 == 5'd0) ? 32'd0 :
                        ((reg_write_en && (write_addr != 5'd0) && (write_addr == read_addr2)) ?
                         write_data : reg_array[read_addr2]);
endmodule

// =======================================================
// Control Unit
// =======================================================
module control_unit (
    input  wire [5:0] opcode,
    output reg        reg_dst,
    output reg        alu_src,
    output reg        mem_to_reg,
    output reg        reg_write,
    output reg        mem_read,
    output reg        mem_write,
    output reg        branch,
    output reg  [1:0] alu_op
);
    always @(*) begin
        reg_dst    = 1'b0;
        alu_src    = 1'b0;
        mem_to_reg = 1'b0;
        reg_write  = 1'b0;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        branch     = 1'b0;
        alu_op     = 2'b00;

        case (opcode)
            6'b000000: begin // R-type
                reg_dst   = 1'b1;
                reg_write = 1'b1;
                alu_op    = 2'b10;
            end
            6'b100011: begin // LW
                alu_src    = 1'b1;
                mem_to_reg = 1'b1;
                reg_write  = 1'b1;
                mem_read   = 1'b1;
                alu_op     = 2'b00;
            end
            6'b101011: begin // SW
                alu_src   = 1'b1;
                mem_write = 1'b1;
                alu_op    = 2'b00;
            end
            6'b000100: begin // BEQ
                branch = 1'b1;
                alu_op = 2'b01;
            end
            default: begin
            end
        endcase
    end
endmodule

module alu_control_unit (
    input  wire [1:0] alu_op,
    input  wire [5:0] funct,
    output reg  [2:0] alu_control
);
    always @(*) begin
        case (alu_op)
            2'b00: alu_control = 3'b000; // LW/SW => ADD
            2'b01: alu_control = 3'b001; // BEQ => SUB
            2'b10: begin
                case (funct)
                    6'b100000: alu_control = 3'b000; // ADD
                    6'b100010: alu_control = 3'b001; // SUB
                    6'b100100: alu_control = 3'b010; // AND
                    6'b100101: alu_control = 3'b011; // OR
                    default:   alu_control = 3'b000;
                endcase
            end
            default: alu_control = 3'b000;
        endcase
    end
endmodule

// =======================================================
// Backing Instruction Memory
// =======================================================
module instruction_memory (
    input  wire [31:0] address,
    output wire [31:0] instruction
);
    reg [31:0] mem [0:255];
    integer i;

    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            mem[i] = 32'h0000_0000;
        end
    end

    assign instruction = mem[address[9:2]];
endmodule

// =======================================================
// Backing Data Memory
// =======================================================
module data_memory (
    input  wire        clk,
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire [31:0] address,
    input  wire [31:0] write_data,
    output wire [31:0] read_data
);
    reg [31:0] mem [0:255];
    integer i;
    wire [7:0] word_addr;

    assign word_addr = address[9:2];
    assign read_data = mem_read ? mem[word_addr] : 32'd0;

    always @(posedge clk) begin
        if (mem_write) begin
            mem[word_addr] <= write_data;
        end
    end

    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            mem[i] = 32'd0;
        end
    end
endmodule

// =======================================================
// Pipeline Registers
// =======================================================
module if_id_reg (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire        flush,
    input  wire [31:0] if_pc_plus4,
    input  wire [31:0] if_instruction,
    output reg  [31:0] id_pc_plus4,
    output reg  [31:0] id_instruction
);
    always @(posedge clk) begin
        if (reset || flush) begin
            id_pc_plus4    <= 32'd0;
            id_instruction <= 32'd0;
        end else if (enable) begin
            id_pc_plus4    <= if_pc_plus4;
            id_instruction <= if_instruction;
        end
    end
endmodule

module id_ex_reg (
    input  wire        clk,
    input  wire        reset,
    input  wire        flush,
    input  wire        id_reg_dst,
    input  wire        id_alu_src,
    input  wire        id_mem_to_reg,
    input  wire        id_reg_write,
    input  wire        id_mem_read,
    input  wire        id_mem_write,
    input  wire        id_branch,
    input  wire [2:0]  id_alu_control,
    input  wire [31:0] id_pc_plus4,
    input  wire [31:0] id_read_data1,
    input  wire [31:0] id_read_data2,
    input  wire [31:0] id_sign_ext_imm,
    input  wire [4:0]  id_rs,
    input  wire [4:0]  id_rt,
    input  wire [4:0]  id_rd,
    output reg         ex_reg_dst,
    output reg         ex_alu_src,
    output reg         ex_mem_to_reg,
    output reg         ex_reg_write,
    output reg         ex_mem_read,
    output reg         ex_mem_write,
    output reg         ex_branch,
    output reg  [2:0]  ex_alu_control,
    output reg  [31:0] ex_pc_plus4,
    output reg  [31:0] ex_read_data1,
    output reg  [31:0] ex_read_data2,
    output reg  [31:0] ex_sign_ext_imm,
    output reg  [4:0]  ex_rs,
    output reg  [4:0]  ex_rt,
    output reg  [4:0]  ex_rd
);
    always @(posedge clk) begin
        if (reset || flush) begin
            ex_reg_dst      <= 1'b0;
            ex_alu_src      <= 1'b0;
            ex_mem_to_reg   <= 1'b0;
            ex_reg_write    <= 1'b0;
            ex_mem_read     <= 1'b0;
            ex_mem_write    <= 1'b0;
            ex_branch       <= 1'b0;
            ex_alu_control  <= 3'b000;
            ex_pc_plus4     <= 32'd0;
            ex_read_data1   <= 32'd0;
            ex_read_data2   <= 32'd0;
            ex_sign_ext_imm <= 32'd0;
            ex_rs           <= 5'd0;
            ex_rt           <= 5'd0;
            ex_rd           <= 5'd0;
        end else begin
            ex_reg_dst      <= id_reg_dst;
            ex_alu_src      <= id_alu_src;
            ex_mem_to_reg   <= id_mem_to_reg;
            ex_reg_write    <= id_reg_write;
            ex_mem_read     <= id_mem_read;
            ex_mem_write    <= id_mem_write;
            ex_branch       <= id_branch;
            ex_alu_control  <= id_alu_control;
            ex_pc_plus4     <= id_pc_plus4;
            ex_read_data1   <= id_read_data1;
            ex_read_data2   <= id_read_data2;
            ex_sign_ext_imm <= id_sign_ext_imm;
            ex_rs           <= id_rs;
            ex_rt           <= id_rt;
            ex_rd           <= id_rd;
        end
    end
endmodule

module ex_mem_reg (
    input  wire        clk,
    input  wire        reset,
    input  wire        ex_mem_to_reg,
    input  wire        ex_reg_write,
    input  wire        ex_mem_read,
    input  wire        ex_mem_write,
    input  wire        ex_branch_taken,
    input  wire [31:0] ex_branch_target,
    input  wire [31:0] ex_alu_result,
    input  wire [31:0] ex_write_data,
    input  wire [4:0]  ex_write_reg_addr,
    output reg         mem_mem_to_reg,
    output reg         mem_reg_write,
    output reg         mem_mem_read,
    output reg         mem_mem_write,
    output reg         mem_branch_taken,
    output reg  [31:0] mem_branch_target,
    output reg  [31:0] mem_alu_result,
    output reg  [31:0] mem_write_data,
    output reg  [4:0]  mem_write_reg_addr
);
    always @(posedge clk) begin
        if (reset) begin
            mem_mem_to_reg     <= 1'b0;
            mem_reg_write      <= 1'b0;
            mem_mem_read       <= 1'b0;
            mem_mem_write      <= 1'b0;
            mem_branch_taken   <= 1'b0;
            mem_branch_target  <= 32'd0;
            mem_alu_result     <= 32'd0;
            mem_write_data     <= 32'd0;
            mem_write_reg_addr <= 5'd0;
        end else begin
            mem_mem_to_reg     <= ex_mem_to_reg;
            mem_reg_write      <= ex_reg_write;
            mem_mem_read       <= ex_mem_read;
            mem_mem_write      <= ex_mem_write;
            mem_branch_taken   <= ex_branch_taken;
            mem_branch_target  <= ex_branch_target;
            mem_alu_result     <= ex_alu_result;
            mem_write_data     <= ex_write_data;
            mem_write_reg_addr <= ex_write_reg_addr;
        end
    end
endmodule

module mem_wb_reg (
    input  wire        clk,
    input  wire        reset,
    input  wire        mem_mem_to_reg,
    input  wire        mem_reg_write,
    input  wire [31:0] mem_read_data,
    input  wire [31:0] mem_alu_result,
    input  wire [4:0]  mem_write_reg_addr,
    output reg         wb_mem_to_reg,
    output reg         wb_reg_write,
    output reg  [31:0] wb_read_data,
    output reg  [31:0] wb_alu_result,
    output reg  [4:0]  wb_write_reg_addr
);
    always @(posedge clk) begin
        if (reset) begin
            wb_mem_to_reg     <= 1'b0;
            wb_reg_write      <= 1'b0;
            wb_read_data      <= 32'd0;
            wb_alu_result     <= 32'd0;
            wb_write_reg_addr <= 5'd0;
        end else begin
            wb_mem_to_reg     <= mem_mem_to_reg;
            wb_reg_write      <= mem_reg_write;
            wb_read_data      <= mem_read_data;
            wb_alu_result     <= mem_alu_result;
            wb_write_reg_addr <= mem_write_reg_addr;
        end
    end
endmodule

// =======================================================
// Hazard + Forwarding Units
// =======================================================
module forwarding_unit (
    input  wire       ex_mem_reg_write,
    input  wire       ex_mem_mem_to_reg,
    input  wire [4:0] ex_mem_rd,
    input  wire       mem_wb_reg_write,
    input  wire [4:0] mem_wb_rd,
    input  wire [4:0] id_ex_rs,
    input  wire [4:0] id_ex_rt,
    output reg  [1:0] forward_a,
    output reg  [1:0] forward_b
);
    always @(*) begin
        forward_a = 2'b00;
        forward_b = 2'b00;

        if (ex_mem_reg_write && !ex_mem_mem_to_reg &&
            (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs)) begin
            forward_a = 2'b10;
        end
        if (ex_mem_reg_write && !ex_mem_mem_to_reg &&
            (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rt)) begin
            forward_b = 2'b10;
        end

        if (mem_wb_reg_write && (mem_wb_rd != 5'd0) &&
            !(ex_mem_reg_write && !ex_mem_mem_to_reg &&
              (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs)) &&
            (mem_wb_rd == id_ex_rs)) begin
            forward_a = 2'b01;
        end

        if (mem_wb_reg_write && (mem_wb_rd != 5'd0) &&
            !(ex_mem_reg_write && !ex_mem_mem_to_reg &&
              (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rt)) &&
            (mem_wb_rd == id_ex_rt)) begin
            forward_b = 2'b01;
        end
    end
endmodule

module hazard_detection_unit (
    input  wire       id_ex_mem_read,
    input  wire [4:0] id_ex_rt,
    input  wire [4:0] if_id_rs,
    input  wire [4:0] if_id_rt,
    output reg        stall
);
    always @(*) begin
        if (id_ex_mem_read &&
            (id_ex_rt != 5'd0) &&
            ((id_ex_rt == if_id_rs) || (id_ex_rt == if_id_rt))) begin
            stall = 1'b1;
        end else begin
            stall = 1'b0;
        end
    end
endmodule

// =======================================================
// Direct-Mapped Instruction Cache (16 lines, 1 word/line)
// =======================================================
module instruction_cache (
    input  wire        clk,
    input  wire        reset,
    input  wire        access_en,
    input  wire [31:0] address,
    input  wire [31:0] backing_instruction,
    output wire [31:0] instruction,
    output wire        hit,
    output wire        miss
);
    reg [31:0] data_array [0:15];
    reg [25:0] tag_array  [0:15];
    reg        valid_array[0:15];
    integer i;

    wire [3:0]  index;
    wire [25:0] tag;
    wire        line_hit;

    reg [31:0] access_count;
    reg [31:0] hit_count;
    reg [31:0] miss_count;

    assign index    = address[5:2];
    assign tag      = address[31:6];
    assign line_hit = valid_array[index] && (tag_array[index] == tag);

    assign hit         = access_en && line_hit;
    assign miss        = access_en && !line_hit;
    assign instruction = line_hit ? data_array[index] : backing_instruction;

    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < 16; i = i + 1) begin
                data_array[i]  <= 32'd0;
                tag_array[i]   <= 26'd0;
                valid_array[i] <= 1'b0;
            end
            access_count <= 32'd0;
            hit_count    <= 32'd0;
            miss_count   <= 32'd0;
        end else if (access_en) begin
            access_count <= access_count + 32'd1;
            if (line_hit) begin
                hit_count <= hit_count + 32'd1;
            end else begin
                miss_count <= miss_count + 32'd1;
                data_array[index]  <= backing_instruction;
                tag_array[index]   <= tag;
                valid_array[index] <= 1'b1;
            end
        end
    end
endmodule

// =======================================================
// Direct-Mapped Data Cache (16 lines, 1 word/line)
// =======================================================
module data_cache (
    input  wire        clk,
    input  wire        reset,
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire [31:0] address,
    input  wire [31:0] write_data,
    input  wire [31:0] backing_read_data,
    output wire [31:0] read_data,
    output wire        hit,
    output wire        miss
);
    reg [31:0] data_array [0:15];
    reg [25:0] tag_array  [0:15];
    reg        valid_array[0:15];
    integer i;

    wire        access_en;
    wire [3:0]  index;
    wire [25:0] tag;
    wire        line_hit;

    reg [31:0] access_count;
    reg [31:0] hit_count;
    reg [31:0] miss_count;

    assign access_en = mem_read | mem_write;
    assign index     = address[5:2];
    assign tag       = address[31:6];
    assign line_hit  = valid_array[index] && (tag_array[index] == tag);

    assign hit      = access_en && line_hit;
    assign miss     = access_en && !line_hit;
    assign read_data = mem_read ? (line_hit ? data_array[index] : backing_read_data) : 32'd0;

    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < 16; i = i + 1) begin
                data_array[i]  <= 32'd0;
                tag_array[i]   <= 26'd0;
                valid_array[i] <= 1'b0;
            end
            access_count <= 32'd0;
            hit_count    <= 32'd0;
            miss_count   <= 32'd0;
        end else if (access_en) begin
            access_count <= access_count + 32'd1;

            if (line_hit) begin
                hit_count <= hit_count + 32'd1;
            end else begin
                miss_count <= miss_count + 32'd1;
            end

            // Write-through + write-allocate
            if (mem_write) begin
                data_array[index]  <= write_data;
                tag_array[index]   <= tag;
                valid_array[index] <= 1'b1;
            end else if (mem_read && !line_hit) begin
                data_array[index]  <= backing_read_data;
                tag_array[index]   <= tag;
                valid_array[index] <= 1'b1;
            end
        end
    end
endmodule

// =======================================================
// Pipelined CPU (Step 8)
// =======================================================
module pipelined_cpu (
    input  wire        clk,
    input  wire        reset,
    output wire [31:0] pc_out,
    output wire [31:0] instruction_out
);
    // Performance counters
    reg [31:0] cycle_count;
    reg [31:0] instr_retired_count;
    wire       instr_retire_pulse;

    // ---------------- IF ----------------
    reg  [31:0] pc_reg;
    wire [31:0] if_instruction;
    wire [31:0] if_instruction_backing;
    wire [31:0] if_pc_plus4;

    wire [31:0] branch_target_ex;
    wire        branch_taken_ex;

    wire stall;
    wire pc_write;
    wire if_id_enable;
    wire if_id_flush;
    wire id_ex_flush;

    assign if_pc_plus4  = pc_reg + 32'd4;
    assign pc_write     = ~stall;
    assign if_id_enable = ~stall;
    assign if_id_flush  = branch_taken_ex;
    assign id_ex_flush  = stall | branch_taken_ex;

    always @(posedge clk) begin
        if (reset) begin
            pc_reg <= 32'd0;
        end else if (branch_taken_ex) begin
            pc_reg <= branch_target_ex;
        end else if (pc_write) begin
            pc_reg <= if_pc_plus4;
        end
    end

    instruction_memory imem (
        .address(pc_reg),
        .instruction(if_instruction_backing)
    );

    instruction_cache icache (
        .clk(clk),
        .reset(reset),
        .access_en(pc_write | branch_taken_ex),
        .address(pc_reg),
        .backing_instruction(if_instruction_backing),
        .instruction(if_instruction),
        .hit(),
        .miss()
    );

    // ---------------- IF/ID ----------------
    wire [31:0] id_pc_plus4;
    wire [31:0] id_instruction;

    if_id_reg if_id (
        .clk(clk),
        .reset(reset),
        .enable(if_id_enable),
        .flush(if_id_flush),
        .if_pc_plus4(if_pc_plus4),
        .if_instruction(if_instruction),
        .id_pc_plus4(id_pc_plus4),
        .id_instruction(id_instruction)
    );

    // ---------------- ID ----------------
    wire [5:0]  opcode_id = id_instruction[31:26];
    wire [4:0]  rs_id     = id_instruction[25:21];
    wire [4:0]  rt_id     = id_instruction[20:16];
    wire [4:0]  rd_id     = id_instruction[15:11];
    wire [5:0]  funct_id  = id_instruction[5:0];
    wire [15:0] imm16_id  = id_instruction[15:0];

    wire       reg_dst_id;
    wire       alu_src_id;
    wire       mem_to_reg_id;
    wire       reg_write_id;
    wire       mem_read_id;
    wire       mem_write_id;
    wire       branch_id;
    wire [1:0] alu_op_id;
    wire [2:0] alu_control_id;

    control_unit main_control (
        .opcode(opcode_id),
        .reg_dst(reg_dst_id),
        .alu_src(alu_src_id),
        .mem_to_reg(mem_to_reg_id),
        .reg_write(reg_write_id),
        .mem_read(mem_read_id),
        .mem_write(mem_write_id),
        .branch(branch_id),
        .alu_op(alu_op_id)
    );

    alu_control_unit alu_ctrl (
        .alu_op(alu_op_id),
        .funct(funct_id),
        .alu_control(alu_control_id)
    );

    wire [31:0] sign_ext_imm_id = {{16{imm16_id[15]}}, imm16_id};
    wire [31:0] read_data1_id;
    wire [31:0] read_data2_id;

    // WB wires for regfile
    wire        wb_mem_to_reg;
    wire        wb_reg_write;
    wire [31:0] wb_read_data;
    wire [31:0] wb_alu_result;
    wire [4:0]  wb_write_reg_addr;
    wire [31:0] wb_write_data;

    assign wb_write_data = wb_mem_to_reg ? wb_read_data : wb_alu_result;

    register_file reg_file (
        .clk(clk),
        .reset(reset),
        .reg_write_en(wb_reg_write),
        .read_addr1(rs_id),
        .read_addr2(rt_id),
        .write_addr(wb_write_reg_addr),
        .write_data(wb_write_data),
        .read_data1(read_data1_id),
        .read_data2(read_data2_id)
    );

    // ---------------- ID/EX ----------------
    wire        reg_dst_ex;
    wire        alu_src_ex;
    wire        mem_to_reg_ex;
    wire        reg_write_ex;
    wire        mem_read_ex;
    wire        mem_write_ex;
    wire        branch_ex;
    wire [2:0]  alu_control_ex;
    wire [31:0] pc_plus4_ex;
    wire [31:0] read_data1_ex;
    wire [31:0] read_data2_ex;
    wire [31:0] sign_ext_imm_ex;
    wire [4:0]  rs_ex;
    wire [4:0]  rt_ex;
    wire [4:0]  rd_ex;

    id_ex_reg id_ex (
        .clk(clk),
        .reset(reset),
        .flush(id_ex_flush),
        .id_reg_dst(reg_dst_id),
        .id_alu_src(alu_src_id),
        .id_mem_to_reg(mem_to_reg_id),
        .id_reg_write(reg_write_id),
        .id_mem_read(mem_read_id),
        .id_mem_write(mem_write_id),
        .id_branch(branch_id),
        .id_alu_control(alu_control_id),
        .id_pc_plus4(id_pc_plus4),
        .id_read_data1(read_data1_id),
        .id_read_data2(read_data2_id),
        .id_sign_ext_imm(sign_ext_imm_id),
        .id_rs(rs_id),
        .id_rt(rt_id),
        .id_rd(rd_id),
        .ex_reg_dst(reg_dst_ex),
        .ex_alu_src(alu_src_ex),
        .ex_mem_to_reg(mem_to_reg_ex),
        .ex_reg_write(reg_write_ex),
        .ex_mem_read(mem_read_ex),
        .ex_mem_write(mem_write_ex),
        .ex_branch(branch_ex),
        .ex_alu_control(alu_control_ex),
        .ex_pc_plus4(pc_plus4_ex),
        .ex_read_data1(read_data1_ex),
        .ex_read_data2(read_data2_ex),
        .ex_sign_ext_imm(sign_ext_imm_ex),
        .ex_rs(rs_ex),
        .ex_rt(rt_ex),
        .ex_rd(rd_ex)
    );

    hazard_detection_unit hazard_unit (
        .id_ex_mem_read(mem_read_ex),
        .id_ex_rt(rt_ex),
        .if_id_rs(rs_id),
        .if_id_rt(rt_id),
        .stall(stall)
    );

    // ---------------- EX ----------------
    wire        mem_to_reg_mem;
    wire        reg_write_mem;
    wire        mem_read_mem;
    wire        mem_write_mem;
    wire [31:0] alu_result_mem;
    wire [31:0] write_data_mem;
    wire [4:0]  write_reg_addr_mem;

    wire [1:0]  forward_a_sel;
    wire [1:0]  forward_b_sel;
    wire [31:0] forward_a_data_ex;
    wire [31:0] forward_b_data_ex;
    wire [31:0] alu_operand_a_ex;
    wire [31:0] alu_operand_b_ex;
    wire [31:0] store_data_ex;
    wire [31:0] alu_result_ex;
    wire        zero_flag_ex;
    wire [4:0]  write_reg_addr_ex;

    forwarding_unit fwd_unit (
        .ex_mem_reg_write(reg_write_mem),
        .ex_mem_mem_to_reg(mem_to_reg_mem),
        .ex_mem_rd(write_reg_addr_mem),
        .mem_wb_reg_write(wb_reg_write),
        .mem_wb_rd(wb_write_reg_addr),
        .id_ex_rs(rs_ex),
        .id_ex_rt(rt_ex),
        .forward_a(forward_a_sel),
        .forward_b(forward_b_sel)
    );

    assign forward_a_data_ex = (forward_a_sel == 2'b10) ? alu_result_mem :
                               (forward_a_sel == 2'b01) ? wb_write_data :
                                                          read_data1_ex;

    assign forward_b_data_ex = (forward_b_sel == 2'b10) ? alu_result_mem :
                               (forward_b_sel == 2'b01) ? wb_write_data :
                                                          read_data2_ex;

    assign alu_operand_a_ex  = forward_a_data_ex;
    assign alu_operand_b_ex  = alu_src_ex ? sign_ext_imm_ex : forward_b_data_ex;
    assign store_data_ex     = forward_b_data_ex;
    assign write_reg_addr_ex = reg_dst_ex ? rd_ex : rt_ex;
    assign branch_target_ex  = pc_plus4_ex + (sign_ext_imm_ex << 2);
    assign branch_taken_ex   = branch_ex & zero_flag_ex;

    assign instr_retire_pulse = reg_write_ex | mem_read_ex | mem_write_ex | branch_ex;

    alu ex_alu (
        .operand_a(alu_operand_a_ex),
        .operand_b(alu_operand_b_ex),
        .alu_control(alu_control_ex),
        .alu_result(alu_result_ex),
        .zero_flag(zero_flag_ex)
    );

    // ---------------- EX/MEM ----------------
    ex_mem_reg ex_mem (
        .clk(clk),
        .reset(reset),
        .ex_mem_to_reg(mem_to_reg_ex),
        .ex_reg_write(reg_write_ex),
        .ex_mem_read(mem_read_ex),
        .ex_mem_write(mem_write_ex),
        .ex_branch_taken(branch_taken_ex),
        .ex_branch_target(branch_target_ex),
        .ex_alu_result(alu_result_ex),
        .ex_write_data(store_data_ex),
        .ex_write_reg_addr(write_reg_addr_ex),
        .mem_mem_to_reg(mem_to_reg_mem),
        .mem_reg_write(reg_write_mem),
        .mem_mem_read(mem_read_mem),
        .mem_mem_write(mem_write_mem),
        .mem_branch_taken(),
        .mem_branch_target(),
        .mem_alu_result(alu_result_mem),
        .mem_write_data(write_data_mem),
        .mem_write_reg_addr(write_reg_addr_mem)
    );

    // ---------------- MEM ----------------
    wire [31:0] mem_read_data_backing;
    wire [31:0] mem_read_data_mem;

    data_memory dmem (
        .clk(clk),
        .mem_read(mem_read_mem),
        .mem_write(mem_write_mem),
        .address(alu_result_mem),
        .write_data(write_data_mem),
        .read_data(mem_read_data_backing)
    );

    data_cache dcache (
        .clk(clk),
        .reset(reset),
        .mem_read(mem_read_mem),
        .mem_write(mem_write_mem),
        .address(alu_result_mem),
        .write_data(write_data_mem),
        .backing_read_data(mem_read_data_backing),
        .read_data(mem_read_data_mem),
        .hit(),
        .miss()
    );

    // ---------------- MEM/WB ----------------
    mem_wb_reg mem_wb (
        .clk(clk),
        .reset(reset),
        .mem_mem_to_reg(mem_to_reg_mem),
        .mem_reg_write(reg_write_mem),
        .mem_read_data(mem_read_data_mem),
        .mem_alu_result(alu_result_mem),
        .mem_write_reg_addr(write_reg_addr_mem),
        .wb_mem_to_reg(wb_mem_to_reg),
        .wb_reg_write(wb_reg_write),
        .wb_read_data(wb_read_data),
        .wb_alu_result(wb_alu_result),
        .wb_write_reg_addr(wb_write_reg_addr)
    );

    // Performance counters
    always @(posedge clk) begin
        if (reset) begin
            cycle_count         <= 32'd0;
            instr_retired_count <= 32'd0;
        end else begin
            cycle_count <= cycle_count + 32'd1;
            if (instr_retire_pulse) begin
                instr_retired_count <= instr_retired_count + 32'd1;
            end
        end
    end

    assign pc_out = pc_reg;
    assign instruction_out = if_instruction;
endmodule
