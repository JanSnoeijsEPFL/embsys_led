library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity led is
	port(
		--Avalon interface
		Clk: in std_logic;
		nReset: in std_logic;
	
		Address: in std_logic_vector(5 downto 0);
		ChipSelect: in std_logic;
		Read: in std_logic;
		Write: in std_logic;
		ReadData: out std_logic_vector(7 downto 0);
		WriteData: in std_logic_vector(7 downto 0);
	
	--External interface
		LedData: out std_logic
	);
	
	
end entity led;

architecture rtl of led is
	
	
	-- constants
	type led_type is array (0 to 2) of std_logic_vector(7 downto 0);
	type data_type is array (0 to 15) of led_type;
	constant ZERO : unsigned(7 downto 0) := (others => '0');
	constant DATA_ZERO: data_type := (others => (others => (others => '0')));
	constant CNT_ZERO: unsigned (5 downto 0):= (others => '0');
	constant RGB_CNT_ZERO: unsigned (1 downto 0):= (others => '0');
	constant LED_CNT_ZERO: unsigned (4 downto 0):= (others => '0');
	constant BIT_CNT_ZERO: unsigned (3 downto 0):= (others => '0');
	
	--software accessible registers
	
	-- mapping of the registers
	-- 49 used registers. 48 for Data and 1 for control
	-- the addresses are 6 bit vectors
	-- 4 first bits are encoding the number of the LED. (0000--> LED15 1111-->LED0)
	-- 2 last bits encode the color (00--> BLUE, 01--> RED, 10--> GREEN)
	-- the address of the control register is : "000011"
	-- the control register is set like this ("01" -> start, "00" --> ready, "11"--> busy) You can write "01" in the control register, the 2 other values are set internally.
	-- the other 15 addresses are unused and have the following code ("XXXX11" except "000011")
	
	-- The mapping is controlled by the DPU_REG process but I will have to modify it.
	-- In this version the registers are not readable by the software but you can write them (If you need to read the Led values in the software or control register values please tell me !)
	
	signal data_reg, data_next : data_type; --data_type is an array of 16 (Leds) x 3 (GRB) x 8 (bits)
	signal ctr_reg, ctr_next: unsigned (1 downto 0);
	
	
	signal  wr0_reg, wr0_next, wr1_reg, wr1_next: unsigned (5 downto 0);
	signal addr_led: std_logic_vector (3 downto 0);
	signal addr_color: std_logic_vector (1 downto 0);
	
	signal rgb_cnt_reg,rgb_cnt_next: unsigned(1 downto 0);
	signal led_cnt_reg, led_cnt_next: unsigned (4 downto 0);
	signal bit_cnt_reg, bit_cnt_next: unsigned (3 downto 0);
	
	-- states & state register	
	type state_type is (ST_IDLE, ST_LOAD, ST_WR0, ST_WR1);
	signal state_reg, state_next : state_type;

	-- status signals
	signal LoadFinish, Wr0Finish, Wr1Finish, FirstMSB: std_logic;
 	signal next_bit: std_logic_vector(1 downto 0);
 	signal led_cnt0, rgb_cnt0, bit_cnt0, writing, loading: std_logic;
	-- functional output

	signal wr0_dec, wr1_dec: unsigned (5 downto 0);
	signal led_dec: unsigned (4 downto 0);
	signal rgb_dec: unsigned (1 downto 0);
	signal bit_dec: unsigned (3 downto 0);
begin
	
	CU_REG: process(Clk, nReset)
	begin
		if nReset ='1' then
			state_reg <= ST_IDLE;
		elsif rising_edge(Clk) then
			state_reg <= state_next;
		end if;
	end process CU_REG;
	
	-- (CU) next_state logic

	CU_NSL: process (state_reg, ctr_reg, LoadFinish, Wr0Finish, Wr1Finish, FirstMSB, next_bit )
	begin
		state_next <= state_reg;
		case state_reg is
		when ST_IDLE => if ctr_reg = "01" then
							state_next <= ST_LOAD;
						end if;
		when ST_LOAD => if LoadFinish = '1' then
							if FirstMSB = '0' then
								state_next <= ST_WR0;
							else
								state_next <= ST_WR1;
							end if;
						end if;
		when ST_WR0 => if Wr0Finish = '1' then
							if next_bit = "00" then
								state_next <= ST_WR0;
							elsif next_bit = "01" then
								state_next <= ST_WR1;
							else
								state_next <= ST_IDLE;
							end if;
						end if;
		when ST_WR1 => if Wr1Finish = '1' then
							if next_bit = "00" then
								state_next <= ST_WR0;
							elsif next_bit = "01" then
								state_next <= ST_WR1;
							else
								state_next <= ST_IDLE;
							end if;
						end if;
			end case;
	end process CU_NSL;
	
	LoadFinish <= '1' when led_cnt_reg = CNT_ZERO;
	Wr0Finish <= '1' when wr0_next = CNT_ZERO;
	Wr1Finish <= '1' when wr1_next = CNT_ZERO;
	rgb_cnt0 <= '1' when rgb_cnt_reg = RGB_CNT_ZERO;
	led_cnt0 <= '1' when led_cnt_next = LED_CNT_ZERO;
	bit_cnt0 <= '1' when bit_cnt_reg = BIT_CNT_ZERO;
	
	
addr_led <= Address(5 downto 2);
addr_color <= Address(1 downto 0);

DPU_REG: process (Clk, nReset)
begin
		if nReset = '0' then
			data_reg <= DATA_ZERO;
			led_cnt_reg <= (others => '0');
			rgb_cnt_reg <= (others => '0');
			wr0_reg <= (others => '0');
			wr1_reg <= (others => '0');
		elsif rising_edge(Clk) then
			led_cnt_reg <= led_cnt_next;
			rgb_cnt_reg <= rgb_cnt_next;
			wr0_reg <=  wr0_next;
			wr1_reg <= wr1_next;
			data_reg <= data_next;
			if ChipSelect ='1' and Write='1' then
				if Address = "000011" then
					ctr_reg <= unsigned(WriteData(1 downto 0));
				else
					data_reg (to_integer(unsigned(addr_led)))(to_integer(unsigned(addr_color))) <= WriteData;
				end if;
				
			end if;
		end if;
	end process DPU_REG;
	
	-- (DPU) routing mux
	DPU_RMUX: process (state_reg, data_reg,led_cnt_reg, wr0_reg, wr1_reg, led_dec, wr0_dec, wr1_dec)
	begin
		data_next <= data_reg;
		led_cnt_next <= led_cnt_reg;
		wr0_next <= wr0_reg;
		wr1_next <= wr1_reg;
		led_cnt_next <= (others => '1');
		wr0_next <= (others => '1');
		wr1_next <= (others => '1');
		loading <= '0';
		writing <= '0';
		case state_reg is
			when ST_IDLE => null;
			when ST_LOAD => led_cnt_next <= led_dec;
							loading <= '1';
			when ST_WR0 => wr0_next <= wr0_dec;
							writing <= '1';
			when ST_WR1 => wr1_next <= wr1_dec;
							writing <= '1';
		end case;
	end process DPU_RMUX;
	
--	DPU_LOAD: process(led_cnt_reg, rgb_cnt_reg, rgb_cnt0, WriteData)
--		variable rgb_cnt: integer:= 0;
--		variable led_cnt: integer:= 0;
--	begin
--		rgb_cnt:=to_integer(rgb_cnt_reg);
--		led_cnt:=to_integer(led_cnt_reg);
--		if loading = '1' then
--			data_reg (led_cnt)(rgb_cnt) <= WriteData;
--			if rgb_cnt0 = '1' then
--				rgb_dec <= (others => '1');
--				led_dec <= led_cnt_reg-1;
--			else
--				rgb_dec <= rgb_cnt_reg-1;
--			end if;
--		end if;
		
	end process DPU_LOAD;
	
	DPU_WRITE: process(led_cnt_reg, rgb_cnt_reg, bit_cnt_reg)
		variable rgb_cnt: integer:= 0;
		variable led_cnt: integer:= 0;
		variable bit_cnt: integer:= 0;
		
	begin
		led_cnt:=to_integer(led_cnt_reg);
		rgb_cnt:=to_integer(rgb_cnt_reg);
		bit_cnt:=to_integer(bit_cnt_reg);
	
		if writing = '1' then	
			next_bit <= '0' & data_reg (led_cnt)(rgb_cnt)(bit_cnt);
		
			if bit_cnt0 ='1' then
			bit_dec <= (others => '1');
				if rgb_cnt0 = '1' then
					rgb_dec <= (others => '1');
					led_dec <= led_cnt_reg-1;
				else
					rgb_dec <= rgb_cnt_reg-1;
				end if;
			else
				bit_dec <= bit_cnt_reg-1;
			end if;
		end if;	

	end process DPU_WRITE;

	DPU_WR0: process
		variable wr0_cnt: integer:= 0;
	begin
		wr0_cnt:=to_integer(wr0_reg);
		
		if wr0_cnt >= 43 then
			LedData <= '0';
		else
			LedData <= '1';
		end if;
		wr0_dec <= wr0_reg-1;
	end process DPU_WR0;
	
	DPU_WR1: process
		variable wr1_cnt: integer:= 0;
	begin
		wr1_cnt:=to_integer(wr1_reg);

		if wr1_cnt >= 23 then
			LedData <= '0';
		else
			LedData <= '1';
		end if;
		wr1_dec <= wr1_reg-1;
	end process DPU_WR1;
end architecture rtl;	