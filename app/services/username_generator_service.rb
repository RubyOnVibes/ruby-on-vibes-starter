# frozen_string_literal: true

class UsernameGeneratorService
  ADJECTIVES = %w[
    agile ambitious bold brave bright brilliant calm cheerful clever cosmic
    creative curious daring dazzling devoted diligent dynamic eager earnest
    efficient elegant energetic enthusiastic epic eternal excellent exotic
    expert fabulous fair faithful famous fancy fast fearless fierce fiery
    fine flashy flying focused fortunate free fresh friendly frost fun
    funky gentle giant gifted glad gleaming glorious golden good graceful
    grand grateful great green growing happy harmonic hasty healthy heavy
    helpful heroic hidden high honest hopeful hot humble icy ideal immortal
    infinite innocent inspired intense inventive iron jade jazzy jolly joyful
    keen kind large lasting lavish lazy leading legendary light lively logical
    lone lovely loyal lucky lunar magic majestic major mellow melodic merry
    mighty mindful misty modern modest moonlit musical mystic natural neat
    neutral nice nimble noble nonstop normal novel odd omega open optimal
    orange organic original outer pacific pale peaceful perfect persistent
    pink placid plain playful pleasant plucky plum poetic polished polite
    popular positive powerful precious premium pretty prime pristine proud
    pure purple quantum quick quiet radiant rapid rare real red regal
    relaxed reliable remarkable resilient rich rising robust rosy royal ruby
    rustic sacred safe sandy sapphire scarlet secret serene sharp shiny
    silent silky silver simple sincere skilled sleek slim smart smooth
    snowy social soft solar solid sonic sparkling special speedy spiritual
    splendid spotless spring square stable star steady stellar still stormy
    strange strong stunning sublime subtle successful sudden sunny super
    supreme sure sweet swift talented tame tasty tender terrific thankful
    thick thin tidy timely tiny top total tough tranquil trendy tropical
    true trusty turbo ultimate ultra unique united universal unusual upbeat
    upper urban useful valid vast velvet vibrant violet virtual vital vivid
    warm wealthy welcome western white whole wicked wild willing winter wise
    witty wonderful worthy yellow young zany zealous zen zesty zippy
  ].freeze

  NOUNS = %w[
    ace agent anchor angel anvil apex apple arch arrow artist atom aurora
    badge badger baker bamboo bandit banner baron basket bass beach beacon
    bear beast beaver bell berry bird bishop blade blaze bloom bolt bone
    boss bounty branch breeze bridge brook bubble buffalo builder burst
    butter button cactus camel camp candle canyon captain card cardinal
    castle cat cedar chain champion cheetah chief cipher citrus cliff cloud
    clover cobra comet compass condor cookie coral cosmos cougar cove coyote
    crane crater creek cricket crimson crow crown crystal current dagger
    dancer dawn deer delta desert diamond dingo disco dolphin dome dragon
    drake dream drift driver drone drum duck dune eagle echo edge elder
    elk ember engine epoch express falcon feather fern finch fire fish
    flame flash flight flower flux fog forest forge fossil fountain fox
    frost fury galaxy gate gator gazelle gear ghost giant ginger glacier
    glider globe goat goblin gold goose gorilla grace grain grove guitar
    gull hacker hammer harbor hare hawk heart hedge hero heron hill hippo
    hollow hood horizon hornet hound hunter hydra igloo iguana impact inlet
    jade jaguar jasmine java jester jewel judge jungle keeper kelp kernel
    kettle kite knight koala lancer lane lark laser lattice leaf legend
    lemur lens leopard light lion lodge lotus lynx machine magnet mango
    mantis maple marble marshal mason master meadow melon mesa meteor mind
    mint mist monarch monkey moon moose mortar moss motor mouse mustang
    myth nebula needle neptune nest night ninja noble nomad nova oak oasis
    ocean olive omega onyx opera oracle orbit orchid otter owl panda panther
    parrot path paw peak pearl pelican pepper phantom phoenix pine pioneer
    pixel planet plasma plaza plum pocket poet polar pond pony portal poster
    prairie prism probe pulse puma python quail quantum quartz quest quill
    rabbit radish rain raven realm rebel reef rhino ridge rider ring river
    robin rocket root rose rover ruby runner sage salmon sand saturn scale
    scout seal seed seeker serpent shade shadow shark sheep shell shield
    shore shrub silk silver sketch skull sky slate sloth smith smoke snail
    snake snow socket solar song sonic soul source spark sparrow spear
    sphinx spider spiral spirit sprout square squirrel stable staff stag
    stamp star steam steel storm stream stripe summit sun sunset surf
    swallow swan swift sword symbol table talon tank target temple terra
    thistle thorn thunder tide tiger timber titan toast torch tower trail
    tree tribe trident troll trophy trout tulip tunnel turkey turtle tusk
    valley vapor vault vector venom venus vertex viper vista void volt
    vortex voyager vulture walrus warden wasp water wave whale wheat whisper
    willow wind wing winter wizard wolf wonder woods world wren yacht yak
    yarn yeti zebra zenith zephyr zero zinc zodiac zone
  ].freeze

  MAX_ATTEMPTS = 10

  class << self
    def generate
      MAX_ATTEMPTS.times do
        candidate = build_username
        return candidate unless User.exists?(username: candidate)
      end
      raise "Failed to generate unique username after #{MAX_ATTEMPTS} attempts"
    end

    private

    def build_username
      "#{ADJECTIVES.sample}_#{NOUNS.sample}_#{SecureRandom.hex(2)}".downcase
    end
  end
end
