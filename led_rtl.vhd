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
	-- the other 15 addresses are unused and have the following code ("XXXX11" except "000011")

	
	signal data_reg, data_next : data_type; --data_type is an array of 16 (Leds) x 3 (GRB) x 8 (bits)
	
	
	signal ctr_reg, ctr_next: unsigned(1 downto 0); -- writable register ("01" --> Start writing data in registers, "10" --> Finish writing data in registers/start turning LEDs on)
	signal status_reg, status_next: unsigned(1 downto 0); -- readable register ("00" --> Ready, "01" --> Loading (When loading the led registers are writable),  "11" -->  Busy)
	
	signal wr0_reg, wr0_next, wr1_reg, wr1_next: unsigned (5 downto 0);
	signal addr_led: std_logic_vector (3 downto 0);
	signal addr_color: std_logic_vector (1 downto 0);
	signal led_data0, led_data1: std_logic;
	
	signal rgb_cnt_reg,rgb_cnt_next: unsigned(1 downto 0);
	signal led_cnt_reg, led_cnt_next: unsigned (3 downto 0);
	signal bit_cnt_reg, bit_cnt_next: unsigned (2 downto 0);
	
	-- states & state register	
	type state_type is (ST_IDLE, ST_LOAD, ST_WR0, ST_WR1);
	signal state_reg, state_next : state_type;

	-- status signals
	signal Wr0Finish, Wr1Finish, FirstMSB, next_bit: std_logic:= '0';
 
 	signal led_cnt0, rgb_cnt0, bit_cnt0: std_logic:='0';
	-- functional output

	signal wr0_dec, wr1_dec: unsigned (5 downto 0):= (others => '0');
	signal led_dec: unsigned (3 downto 0):= (others => '0');
	signal rgb_dec: unsigned (1 downto 0):= (others => '0');
	signal bit_dec: unsigned (2 downto 0):= (others => '0');
begin
	
	CU_REG: process(Clk, nReset)
	begin
		if nReset ='0' then
			state_reg <= ST_IDLE;
		elsif rising_edge(Clk) then
			state_reg <= state_next;
		end if;
	end process CU_REG;
	
	-- (CU) next_state logic

	CU_NSL: process (state_reg, ctr_reg, Wr0Finish, Wr1Finish, FirstMSB, next_bit, led_cnt0)
	begin
		state_next <= state_reg;
		case state_reg is
		when ST_IDLE => if ctr_reg = "01" then
							state_next <= ST_LOAD;
						end if;
		when ST_LOAD => if ctr_reg = "10" then
							if FirstMSB = '0' then
								state_next <= ST_WR0;
							else
								state_next <= ST_WR1;
							end if;
						end if;
		when ST_WR0 => if led_cnt0 = '1' then
							state_next <= ST_IDLE;
						else
							if Wr0Finish = '1' then
								if next_bit = '0' then
									state_next <= ST_WR0;
								elsif next_bit = '1' then
									state_next <= ST_WR1;
								end if;
							end if;
						end if;
		when ST_WR1 =>-- if led_cnt0 = '1' then
							--state_next <= ST_IDLE;
						--else
							if Wr1Finish = '1' then
								if next_bit = '0' then
									state_next <= ST_WR0;
								elsif next_bit = '1' then
									state_next <= ST_WR1;
								end if;
							end if;
						--end if;
			end case;
	end process CU_NSL;
	
	Wr0Finish <= '1' when wr0_reg = CNT_ZERO else '0';
	Wr1Finish <= '1' when wr1_reg = CNT_ZERO else '0';
	rgb_cnt0 <= '1' when rgb_cnt_reg = RGB_CNT_ZERO else '0';
	led_cnt0 <= '1' when led_cnt_next = LED_CNT_ZERO else '0';
	bit_cnt0 <= '1' when bit_cnt_reg = BIT_CNT_ZERO else '0';
	bit_dec <= bit_cnt_reg - 1;
	rgb_dec <= rgb_cnt_reg - 2 when rgb_cnt_reg = "00" else rgb_cnt_reg -1 ;
	led_dec <= led_cnt_reg - 1;
	
addr_led <= Address(5 downto 2);
addr_color <= Address(1 downto 0);

DPU_REG: process (Clk, nReset)
begin
		if nReset = '0' then
			data_reg <= DATA_ZERO;
			led_cnt_reg <= (others => '0');
			rgb_cnt_reg <= (others => '0');
			bit_cnt_reg <= (others => '0');
			wr0_reg <= (others => '0');
			wr1_reg <= (others => '0');
			ctr_reg <= (others => '0');
			status_reg <= (others => '0');
		elsif rising_edge(Clk) then
			led_cnt_reg <= led_cnt_next;
			rgb_cnt_reg <= rgb_cnt_next;
			bit_cnt_reg <= bit_cnt_next;
			wr0_reg <=  wr0_next;
			wr1_reg <= wr1_next;
			data_reg <= data_next;
			ctr_reg <= ctr_next;
			status_reg <= status_next;
		end if;
	end process DPU_REG;
	
	-- (DPU) routing mux
	DPU_RMUX: process (state_reg,led_cnt_reg, wr0_reg, wr1_reg, wr0_dec, wr1_dec, led_dec, rgb_dec, bit_dec, rgb_cnt_reg, 
		bit_cnt_reg, bit_cnt0, rgb_cnt0, Wr0Finish, Wr1Finish, led_data0, led_data1, status_reg)
	begin
		led_cnt_next <= led_cnt_reg;
		rgb_cnt_next <= rgb_cnt_reg;
		bit_cnt_next <= bit_cnt_reg;
		wr0_next <= wr0_reg;
		wr1_next <= wr1_reg;
		status_next <= status_reg;
		LedData <= '0';
		case state_reg is
			when ST_IDLE => status_next <= "00";
			when ST_LOAD => status_next <= "01";
							LedData <= '0';
							wr0_next <= to_unsigned(62, 6);
							wr1_next <= to_unsigned(62, 6);
							led_cnt_next <= to_unsigned(15, 4);
							rgb_cnt_next <= to_unsigned(2, 2);
							bit_cnt_next <= to_unsigned(7, 3);
			when ST_WR0 =>  status_next <= "11";
						    LedData<= led_data0;
							wr0_next <= wr0_dec;
							if Wr0Finish = '1' then
								bit_cnt_next <= bit_dec;
								if bit_cnt0 = '1' then
									rgb_cnt_next <= rgb_dec;
									if rgb_cnt0 = '1' then
										led_cnt_next <= led_dec;
								end if;
							end if;
						end if;
			when ST_WR1 =>  status_next <= "11";
							LedData<=led_data1;
							wr1_next <= wr1_dec;
							if Wr1Finish = '1' then
								bit_cnt_next <= bit_dec;
								if bit_cnt0 = '1' then
									rgb_cnt_next <= rgb_dec;
									if rgb_cnt0 = '1' then
										led_cnt_next <= led_dec;
								end if;
							end if;
						end if;
						
		end case;
	end process DPU_RMUX;
	
DPU_LOAD: process(addr_led, addr_color, WriteData, Write, Address, ChipSelect)
	begin
		if ChipSelect ='1' and Write='1' then
			if Address = "000011" then
					ctr_next <= unsigned(WriteData(1 downto 0));
			else
				if Address = "111110" and WriteData(7) ='1' then
					FirstMSB <= '1';
				else
					FirstMSB <= '0';
				end if;
				if (addr_color /= "11") then
					data_next (to_integer(unsigned(addr_led)))(to_integer(unsigned(addr_color))) <= WriteData;
				end if;
			end if;
		end if;
	end process DPU_LOAD;
	
DPU_READ: process(status_reg, ChipSelect, Address, Read)
begin
	if ChipSelect = '1' and Read = '1' then
		ReadData <= (others => '0');
		if Address = "000111" then
			ReadData <= "000000" & std_logic_vector(status_reg);
		end if;
	end if;
	end process DPU_READ;
	
	
	DPU_WRITE: process(led_cnt_reg, rgb_cnt_reg, bit_cnt_reg, data_reg)
		variable rgb_cnt: integer:= 0;
		variable led_cnt: integer:= 0;
		variable bit_cnt: integer:= 0;
	
	begin
		led_cnt:=to_integer(led_cnt_reg);
		rgb_cnt:=to_integer(rgb_cnt_reg);
		bit_cnt:=to_integer(bit_cnt_reg);
		if (led_cnt <= 15 and rgb_cnt <= 2 and bit_cnt <= 7) then
			next_bit <= data_reg (led_cnt)(rgb_cnt)(bit_cnt);
		end if;
	end process DPU_WRITE;

	DPU_WR0: process(wr0_reg)
		variable wr0_cnt: integer:= 0;
	begin
		wr0_cnt:=to_integer(wr0_reg);

		if wr0_cnt >= 43 then
			led_data0 <= '1';
		else
			led_data0 <= '0';
		end if;
		wr0_dec <= wr0_reg-1;
	
	end process DPU_WR0;
	
	DPU_WR1: process(wr1_reg)
		variable wr1_cnt: integer:= 0;
	begin
		wr1_cnt:=to_integer(wr1_reg);
		
		if wr1_cnt >= 23 then
			led_data1 <= '1';
		else
			led_data1 <= '0';
		end if;
		wr1_dec <= wr1_reg-1;
		
	end process DPU_WR1;
	
end architecture rtl;	