#!/usr/bin/env bash

#important variables
declare -ia board    # array that keeps track of game status
declare -i pieces    # number of pieces present on board
declare -i score=0   # score variable
declare -i flag_skip # flag that prevents doing more than one operation on
                     # single field in one step
declare -i moves     # stores number of possible moves to determine if player lost
                     # the game
declare ESC=$'\e'    # escape byte

declare header="2048 (https://github.com/rhoit/2048bash)"

#default config
declare -i board_size=4
declare -i target=2048

exec 3>/dev/null     # no logging by default

trap "end_game 0; exit" INT #handle INT signal

# Generate new piece on the board
# inputs:
#         $board  - original state of the game board
#         $pieces - original number of pieces
# outputs:
#         $board  - new state of the game board
#         $pieces - new number of pieces
function generate_piece {
  while true; do
    let pos=RANDOM%fields_total
    let board[$pos] || {
      let value=RANDOM%10?2:4
      board[$pos]=$value
      last_added=$pos
      printf "Generated new piece with value $value at position [$pos]\n" >&3
      break;
    }
  done
  let pieces++
}

# perform push operation between two pieces
# inputs:
#         $1 - push position, for horizontal push this is row, for vertical column
#         $2 - recipient piece, this will hold result if moving or joining
#         $3 - originator piece, after moving or joining this will be left empty
#         $4 - direction of push, can be either "up", "down", "left" or "right"
#         $5 - if anything is passed, do not perform the push, only update number
#              of valid moves
#         $board - original state of the game board
# outputs:
#         $change    - indicates if the board was changed this round
#         $flag_skip - indicates that recipient piece cannot be modified further
#         $board     - new state of the game board

function push_pieces {
  case $4 in
    "up")
      let "first=$2*$board_size+$1"
      let "second=($2+$3)*$board_size+$1"
      ;;
    "down")
      let "first=(index_max-$2)*$board_size+$1"
      let "second=(index_max-$2-$3)*$board_size+$1"
      ;;
    "left")
      let "first=$1*$board_size+$2"
      let "second=$1*$board_size+($2+$3)"
      ;;
    "right")
      let "first=$1*$board_size+(index_max-$2)"
      let "second=$1*$board_size+(index_max-$2-$3)"
      ;;
  esac
  let ${board[$first]} || {
    let ${board[$second]} && {
      if test -z $5; then
        board[$first]=${board[$second]}
        let board[$second]=0
        let change=1
        printf "move piece with value ${board[$first]} from [$second] to [$first]\n" >&3
      else
        let moves++
      fi
      return
    }
    return
  }
  let ${board[$second]} && let flag_skip=1
  let "${board[$first]}==${board[second]}" && {
    if test -z $5; then
      let board[$first]*=2
      let "board[$first]==$target" && end_game 1
      let board[$second]=0
      let pieces-=1
      let change=1
      let score+=${board[$first]}
      printf "joined piece from [$second] with [$first], new value=${board[$first]}\n" >&3
    else
      let moves++
    fi
  }
}

function apply_push {
	printf "\n\ninput: $1 key\n" >&3
	for ((i=0; i <= $index_max; i++)); do
		for ((j=0; j <= $index_max; j++)); do
			flag_skip=0
			let increment_max=index_max-j
			for ((k=1; k <= $increment_max; k++)); do
				let flag_skip && break
				push_pieces $i $j $k $1 $2
			done
		done
	done
	box_board_update
}

function check_moves {
  let moves=0
  apply_push up fake
  apply_push down fake
  apply_push left fake
  apply_push right fake
}

function key_react {
  let change=0
  read -d '' -sn 1
  test "$REPLY" = "$ESC" && {
    read -d '' -sn 1 -t1
    test "$REPLY" = "[" && {
      read -d '' -sn 1 -t1
      case $REPLY in
        A) apply_push up;;
        B) apply_push down;;
        C) apply_push right;;
        D) apply_push left;;
      esac
    }
  }
}

function end_game {
  let $1 && {
    echo "Congratulations you have achieved $target"
    exit
  }
  box_board_terminate
  tput cup 9 0
  figlet -c -w $COLUMNS "GAME OVER"
  tput cup 22 80
  stty echo
  tput cnorm
}

function help {
  cat <<END_HELP
Usage: $1 [-b INTEGER] [-t INTEGER] [-l FILE] [-h]

  -b			specify game board size (sizes 3-9 allowed)
  -l			specify target score to win (needs to be power of 2)
  -d			log debug info into specified file
  -h			this help

END_HELP
}


#parse commandline options
while getopts "b:t:l:h" opt; do
	case $opt in
		b ) board_size="$OPTARG"
			let '(board_size>=3)&(board_size<=9)' || {
				printf "Invalid board size, please choose size between 3 and 9\n"
				exit -1
			};;
		t ) target="$OPTARG"
			printf "obase=2;$target\n" | bc | grep -e '^1[^1]*$'
			let $? && {
				printf "Invalid target, has to be power of two\n"
				exit -1
			};;
		h ) help $0
			exit 0;;
		l ) exec 3>$OPTARG;;
		\?) printf "Invalid option: -"$opt", try $0 -h\n" >&2
            exit 1;;
		: ) printf "Option -"$opt" requires an argument, try $0 -h\n" >&2
            exit 1;;
	esac
done

# init board
if [ `basename $0` == "bash2048.sh" ]; then
	clear
	let fields_total=board_size*board_size
	let index_max=board_size-1
	for ((i=fields_total; i>= 0; i--)); do
		board[$i]=0;
	done
	let pieces=0
	generate_piece
	first_round=$last_added
	generate_piece
	source board.sh
	box_board_init $board_size
	box_board_print $index_max
	box_board_update
	while true; do
		#print_board
		key_react
		let change && generate_piece
		first_round=-1
		let pieces==fields_total && {
			check_moves
			let moves==0 && end_game 0 #lose the game
		}
	done
fi
