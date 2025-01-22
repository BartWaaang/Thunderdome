import json
from matplotlib import pyplot
import matplotlib.pyplot as plt
from matplotlib import rc

EUR_IN_ETH = 1668

# rc('font',**{'family':'sans-serif','sans-serif':['Helvetica']})
# plt.rcParams['text.latex.preamble'] = [r'\usepackage{lmodern}']
# for Palatino and other serif fonts use:
# rc('font',**{'family':'serif','serif':['Palatino']})
# rc('text', usetex=True)
# rc(
#     'font',
#     family='serif',
#     serif=['Computer Modern Roman'],
#     monospace=['Computer Modern Typewriter'],
#     size=14
# )

with open('/Users/yuhengwang/Code/Thunderdome/data.json') as f:
    data = json.load(f)

def graphToFloat(graph):
    return list(map(lambda x: float(x), graph))

for key in data:
    data[key] = graphToFloat(data[key])

fig, ax = plt.subplots(constrained_layout=True)
fig.set_size_inches(6.2, 6.2)
ax.set_ylim(0.0, 14.0)

x_values = [10, 13, 16, 19, 22,25]

ax.plot(x_values, data['deploy'], 'purple', label='Cost of deployment')
ax.plot(x_values, data['open'], 'r-o', label='Cost of opening')
ax.plot(x_values, data['pessimisticClose'], 'g-o', label='Cost of pessimistic close')
ax.plot(x_values, data['optimisticClose'], 'b-o', label='Cost of optimistic close')
ax.plot(x_values, data['pessimisticVClose'], 'y-o', label='Cost of pessimistic virtual close')

# ax.axvline(x=13, label='Recommended $n$', color='orange', linestyle='--')

ax.set_title('Gas cost of a $\\text{Thunderdome}$')
ax.set_ylabel('USD')

def eur2eth(eur):
    eth = eur / EUR_IN_ETH
    return eth

def eth2eur(eth):
    eur = EUR_IN_ETH * eth
    return eur

secax = ax.secondary_yaxis('right', functions=(eur2eth, eth2eur))
secax.set_ylabel('Ether')
ax.set_xlabel('Number $n$ of $\\text{Wardens}$')
plt.legend()
# plt.axis([0, len(data['open']), 0, 20])

plt.show()

fig.savefig("/Users/yuhengwang/Code/Thunderdome/gasfee.pdf", bbox_inches='tight')

