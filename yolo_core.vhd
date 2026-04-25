LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.cnn_pkg.ALL;

-- ====================================================================
-- Entity: yolo_core
-- Description: Top-level Avalon-MM Read/Write Master controller. 
-- Manages memory streaming, line buffering, convolution, activation, 
-- max pooling, and runtime reconfigurable memory write-back.
-- ====================================================================
entity yolo_core is
    Port ( 
        clk                 : in  std_logic;
        reset_n             : in  std_logic;
        
        -- Memory Interface (Avalon-MM Read/Write Master)
        mem_address         : out std_logic_vector(15 downto 0);
        mem_read            : out std_logic;
        mem_readdata        : in  std_logic_vector(31 downto 0);
        mem_write           : out std_logic;
        mem_writedata       : out std_logic_vector(31 downto 0);
        
        -- CSR Registers (Avalon-MM PIO Inputs from ARM HPS)
        csr_control         : in  std_logic_vector(31 downto 0);
        csr_read            : in  std_logic_vector(31 downto 0);
        csr_write           : in  std_logic_vector(31 downto 0);
        csr_length          : in  std_logic_vector(31 downto 0);
        layer_done          : out std_logic;
        
        -- Debug Stream
        yolo_out            : out std_logic_vector(31 downto 0);
        yolo_valid          : out std_logic
    );
end yolo_core;

architecture arch of yolo_core is

    -- System Configuration
    constant CHANNELS       : integer := 3;
    constant IMG_WIDTH      : integer := 416;
    constant DST_ROW_STRIDE : unsigned(15 downto 0) := to_unsigned(26, 16); 

    -- FSM Definition 
    type state_type is (S_IDLE, S_FETCH_BIAS, S_LATCH_BIAS, S_STREAM_READ, S_LATCH_AND_SHIFT, S_WRITE_BACK, S_DONE);
    signal state : state_type := S_IDLE;

    -- Control Flags (Mapped from PIO)
    signal mode_1x1         : std_logic;
    signal mode_upsample    : std_logic;
    signal start_mac        : std_logic;
	 
	 -- Layer Termination Trackers
    signal total_pixels     : unsigned(31 downto 0) := (others => '0');
    signal completed_pixels : unsigned(31 downto 0) := (others => '0');

    -- Datapath Signals
    signal stream_enable    : std_logic := '0';
    signal current_pixel    : std_logic_vector(15 downto 0) := (others => '0');
    signal spatial_window   : window_3x3;
	 signal channel_count : integer range 0 to CHANNELS := 0;
    
    signal cnn_bias         : std_logic_vector(31 downto 0) := (others => '0');
    signal cnn_first_chan   : std_logic := '0';
    signal cnn_last_chan    : std_logic := '0';
    
    signal cnn_out_valid    : std_logic := '0';
    signal cnn_act_pixel    : std_logic_vector(31 downto 0) := (others => '0');

    -- Max Pool & Output Caching
    type act_row_type is array (0 to IMG_WIDTH - 1) of std_logic_vector(31 downto 0);
    signal act_row_fifo     : act_row_type := (others => (others => '0'));
    signal col_cnt          : integer range 0 to IMG_WIDTH - 1 := 0;
    signal row_cnt          : integer range 0 to IMG_WIDTH - 1 := 0;
    
    signal pool_00, pool_01, pool_10, pool_11 : std_logic_vector(31 downto 0) := (others => '0');
    signal pool_trigger     : std_logic := '0';
    signal pool_out_valid   : std_logic := '0';
    signal pool_max_result  : std_logic_vector(31 downto 0) := (others => '0');

    -- Decoupled Memory Controller Signals
    signal read_ptr         : unsigned(15 downto 0) := (others => '0');
    signal write_ptr        : unsigned(15 downto 0) := (others => '0');
    signal write_pending    : std_logic := '0';
    signal write_cache      : std_logic_vector(31 downto 0) := (others => '0');
    signal upsample_cnt     : integer range 0 to 3 := 0;

begin

    -- Asynchronous PIO Signal Mapping
    mode_1x1      <= csr_control(0);
    mode_upsample <= csr_control(1);
    start_mac     <= csr_control(2);

    -- 1. Input Line Buffer
    input_buffer_inst : component line_buffer
        generic map ( IMAGE_WIDTH => IMG_WIDTH )
        port map (
            clk         => clk,
            reset_n     => reset_n,
            shift_en    => stream_enable,
            pixel_in    => current_pixel,
            window_out  => spatial_window
        );

    -- 2. CNN MAC Pipeline (Now accepting mode_1x1 bypass flag)
    cnn_pipeline_inst : component cnn_cell
        port map (
            clk             => clk,
            reset_n         => reset_n,
            enable          => '1', 
            data_valid      => stream_enable,
            first_channel   => cnn_first_chan,
            last_channel    => cnn_last_chan,
            mode_1x1        => mode_1x1, 
            out_valid       => cnn_out_valid,
            pixel_window    => spatial_window,
            weight_window   => spatial_window, 
            bias_in         => cnn_bias,
            conv_out        => cnn_act_pixel
        );

    -- 3. Max Pooling Layer
    max_pool_inst : component max_pool_2x2
        port map (
            clk         => clk,
            reset_n     => reset_n,
            enable      => '1',
            data_valid  => pool_trigger, 
            pixel_00    => pool_00,
            pixel_01    => pool_01,
            pixel_10    => pool_10,
            pixel_11    => pool_11,
            out_valid   => pool_out_valid,
            max_out     => pool_max_result
        );

    -- ====================================================================
    -- Output Row Cache & Stride-2 Assembly Logic
    -- ====================================================================
    output_cache_process : process(clk, reset_n)
    begin
        if (reset_n = '0') then
            col_cnt      <= 0;
            row_cnt      <= 0;
            pool_trigger <= '0';
            pool_00 <= (others => '0'); pool_01 <= (others => '0');
            pool_10 <= (others => '0'); pool_11 <= (others => '0');
            
        elsif (rising_edge(clk)) then
            pool_trigger <= '0';
            
            if (cnn_out_valid = '1') then
                -- Shift spatial registers
                pool_10 <= pool_11;               
                pool_11 <= cnn_act_pixel;         
                pool_00 <= pool_01;               
                pool_01 <= act_row_fifo(col_cnt); 
                
                -- Cache current pixel for the next row
                act_row_fifo(col_cnt) <= cnn_act_pixel;
                
                -- Stride-2 Evaluation (Triggers Pool only on complete 2x2 blocks)
                if ((col_cnt mod 2 = 1) and (row_cnt mod 2 = 1)) then
                    pool_trigger <= '1';
                end if;
                
                -- Coordinate Tracking
                if (col_cnt = IMG_WIDTH - 1) then
                    col_cnt <= 0;
                    if (row_cnt = IMG_WIDTH - 1) then
                        row_cnt <= 0;
                    else
                        row_cnt <= row_cnt + 1;
                    end if;
                else
                    col_cnt <= col_cnt + 1;
                end if;
            end if;
        end if;
    end process output_cache_process;


    -- ====================================================================
    -- Decoupled Avalon-MM Master State Machine
    -- ====================================================================
    fsm_process : process(clk, reset_n)
    begin
        if (reset_n = '0') then
            state           <= S_IDLE;
            mem_address     <= (others => '0');
            mem_read        <= '0';
            mem_write       <= '0';
            mem_writedata   <= (others => '0');
            stream_enable   <= '0';
            read_ptr        <= (others => '0');
            write_ptr       <= (others => '0');
            write_pending   <= '0';
            write_cache     <= (others => '0');
            yolo_out        <= (others => '0');
            yolo_valid      <= '0';
            upsample_cnt    <= 0;
            channel_count   <= 0;
            cnn_first_chan  <= '0';
            cnn_last_chan   <= '0';
            
        elsif (rising_edge(clk)) then
            -- Default strobes
            mem_read       <= '0';
            mem_write      <= '0';
            stream_enable  <= '0';
            yolo_valid     <= '0';
            cnn_first_chan <= '0';
            cnn_last_chan  <= '0';

            -- INDEPENDENT CATCH: Asynchronously traps valid output
            if (pool_out_valid = '1') then
                write_pending <= '1';
                write_cache   <= pool_max_result;
                yolo_out      <= pool_max_result; 
                yolo_valid    <= '1';
            end if;

            case state is
                
                when S_IDLE =>
                    layer_done <= '0'; -- Clear handshake flag
                    if (start_mac = '1') then
                        read_ptr         <= unsigned(csr_read(15 downto 0));
                        write_ptr        <= unsigned(csr_write(15 downto 0));
                        total_pixels     <= unsigned(csr_length);
                        completed_pixels <= (others => '0');
                        channel_count    <= 0;
                        state            <= S_FETCH_BIAS;
                    end if;
                    
                when S_FETCH_BIAS =>
                    mem_address <= std_logic_vector(read_ptr);
                    mem_read    <= '1';
                    state       <= S_LATCH_BIAS; 
                    
                when S_LATCH_BIAS =>
                    -- Save the bias
                    cnn_bias <= mem_readdata; 
                    read_ptr <= read_ptr + 1;
                    state    <= S_STREAM_READ;

                when S_STREAM_READ =>
                    if (write_pending = '1') then
                        state <= S_WRITE_BACK;
                    else
                        mem_address <= std_logic_vector(read_ptr);
                        mem_read    <= '1';
                        state       <= S_LATCH_AND_SHIFT;
                    end if;
                    
                when S_LATCH_AND_SHIFT =>
                    current_pixel <= mem_readdata(15 downto 0);
                    stream_enable <= '1'; 
                    read_ptr      <= read_ptr + 1;
                    
                    -- Basic Channel Toggling logic to prevent pipeline deadlock
                    if (channel_count = 0) then
                        cnn_first_chan <= '1';
                    end if;
                    
                    if (channel_count = CHANNELS - 1) then
                        cnn_last_chan <= '1';
                        channel_count <= 0; 
                    else
                        channel_count <= channel_count + 1;
                    end if;
                    
                    state <= S_STREAM_READ; 
                    
                when S_WRITE_BACK =>
                    if (mode_upsample = '1') then
                        mem_writedata <= write_cache; 
                        mem_write     <= '1';
                        
                        if (upsample_cnt = 0) then
                            mem_address <= std_logic_vector(write_ptr);
                        elsif (upsample_cnt = 1) then
                            mem_address <= std_logic_vector(write_ptr + 1);
                        elsif (upsample_cnt = 2) then
                            mem_address <= std_logic_vector(write_ptr + DST_ROW_STRIDE);
                        elsif (upsample_cnt = 3) then
                            mem_address <= std_logic_vector(write_ptr + DST_ROW_STRIDE + 1);
                        end if;

                        if (upsample_cnt = 3) then
                            upsample_cnt     <= 0;
                            write_ptr        <= write_ptr + 2; 
                            completed_pixels <= completed_pixels + 1;
                            
                            if (pool_out_valid = '0') then write_pending <= '0'; end if;
                            
                            -- Termination Check
                            if (completed_pixels + 1 >= total_pixels) then
                                state <= S_DONE;
                            else
                                state <= S_STREAM_READ;
                            end if;
                        else
                            upsample_cnt <= upsample_cnt + 1;
                            state        <= S_WRITE_BACK;
                        end if;
                        
                    else
                        mem_address   <= std_logic_vector(write_ptr);
                        mem_writedata <= write_cache;
                        mem_write     <= '1';
                        write_ptr     <= write_ptr + 1;
                        completed_pixels <= completed_pixels + 1;
                        
                        if (pool_out_valid = '0') then write_pending <= '0'; end if;
                        
                        -- Termination Check
                        if (completed_pixels + 1 >= total_pixels) then
                            state <= S_DONE;
                        else
                            state <= S_STREAM_READ;
                        end if;
                    end if;
                    
                when S_DONE =>
                    layer_done <= '1';
                    
                    -- Wait for the C++ script to explicitly clear the start flag 
                    -- before safely dropping back to IDLE.
                    if (start_mac = '0') then
                        state <= S_IDLE;
                    end if;
                    
                when others =>
                    state <= S_IDLE;
            end case;
        end if;
    end process fsm_process;

end arch;