#!/bin/python
import os

def make_top_file():
  """Function that takes a KCU105 targeted ODMB7 top VHDL file and converts
  it to an ODMB7-targeted top VHDL file
  """

  kcu_file = open('../source/odmb7_ucsb_dev.vhd','r')
  odmb_file = open('../odmb_source/odmb7_ucsb_dev.vhd','w')
  kcu_file_contents = kcu_file.read().split('\n')
  in_synthesis_block = False
  in_simulation_block = False

  for line in kcu_file_contents:

    write_line = line

    if 'odmb_simu' in line:
      in_simulation_block = not in_simulation_block
      continue

    if '_kcu' in line:
      in_synthesis_block = not in_synthesis_block
      continue

    if in_synthesis_block:
      continue

    elif 'meta:comment_for_odmb' in line:
      first_nonspace = 0 
      for line_pos in range(len(line)):
        if line[line_pos] != ' ':
          first_nonspace = line_pos
          break
      write_line = line[0:first_nonspace]+'--'+line[first_nonspace:]

    elif 'meta:uncomment_for_odmb' in line:
      first_nonspace = 0 
      for line_pos in range(len(line)):
        if line[line_pos] != ' ':
          first_nonspace = line_pos
          break
      if line[first_nonspace:first_nonspace+2] != '--':
        print('ERROR: meta:uncomment_for_odmb but line not commented')
      else:
        write_line = line[0:first_nonspace]+line[first_nonspace+2:]

    elif in_simulation_block:
      if (len(line) >= 3):
        if line[0:2] == '  ':
          write_line = line[2:]

    odmb_file.write(write_line)
    odmb_file.write('\n')

if __name__=='__main__':
  """This script generates the directory ../odmb_source if it does not
  already exist, and populates it with ODMB7 compatible firmware
  """
  if not os.path.isdir('../odmb_source'):
    os.mkdir('../odmb_source')

  os.system('cp ../constraints/odmb7_ucsb_dev.xdc ../odmb_source/odmb7_ucsb_dev.xdc')
  os.system('cp -r ../source/odmb_vme ../odmb_source/odmb_vme')
  os.system('cp -r ../source/odmb_ctrl ../odmb_source/odmb_ctrl')
  os.system('cp -r ../source/spi ../odmb_source/spi')
  os.system('cp -r ../source/utils ../odmb_source/utils')
  make_top_file() #moves odmb7_ucsb_dev.vhd

