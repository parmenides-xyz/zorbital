# Orbital: A Novel Automated Market Maker for Multi-Stablecoin Pools

## Outline

The future holds a million stablecoins. Today's infrastructure isn't ready.

This paper introduces **Orbital**, an automated market maker for pools of 2, 3, or 10,000 stablecoins.

Orbital unlocks capital efficiency by bringing concentrated liquidity to higher dimensions.

---

## Introduction: The Problem with Current Infrastructure

This is a graph of the reserves of an automated market maker (AMM) between USDC and USDT. When traders add USDT, they get USDC in return. In the middle, where reserves are equal, the coins have the same price. At the edges, one is worthless compared to the other.

### Uniswap V3 and Concentrated Liquidity

Uniswap V3 pioneered the concept of concentrated liquidity. It creates and consolidates mini-AMMs, called ticks, that support more trading with less capital by restricting themselves to only a specified price range. Uniswap v3 allows liquidity providers to create positions between any two tick boundaries, and efficiently aggregates their liquidity so that traders can interact with it as if it were a single pool. However, it only supports pools between two assets.

### Curve's Multi-Asset Approach

Curve created an invariant-based AMM that allows trading of N stablecoins in a single pool. It focuses liquidity around the price of 1. However, Curve uses a uniform strategy for each pool, meaning all liquidity providers in the same pool have the same liquidity profile.

### Orbital's Innovation

Orbital extends customizable concentrated liquidity to pools of three or more stables by drawing tick boundaries as orbits around the $1 equal price point.

Unlike in 2D concentrated liquidity, even if one stablecoin depegs to 0, an Orbital tick can still trade the others at fair prices.

Smaller ticks closer to the equal $1 price point don't need to hold capital in reserve to give out in case one of the coins depegs.

This lets LPs focus their resources where normal trading actually happens, unlocking significant capital efficiency gains.

---

## The Geometry of Orbital Ticks

The full Orbital AMM combines ticks of different sizes so LPs can customize their exposures.

Some might choose to focus narrowly around the $1 point for maximum efficiency, while others might provide wider coverage to earn fees during times of volatility.

### The Toroidal Structure

Under the hood, Orbital ticks are designed with geometric precision. Thanks to symmetry, we can orbit some around the others to obtain a single toroid (donut-like) shape.

This lets us compute trades efficiently onchain regardless of the number of different coins in the pool.

The math below gets pretty dense, but it's just trying to formalize a relatively simple visual intuition.

### 3D Case Analysis

In the 3D case, depicted above, the base Orbital AMM is a sphere. We only show 1/8th of the sphere in the animation because it's the only relevant part assuming prices stay non-negative.

The *tick* in the diagram refers to the part of the sphere inside the red circle. The red circle itself forms the *boundary* of the tick. Note that, unlike in Uniswap V3, Orbital ticks actually overlap, so that larger ones fully contain smaller ones.

### Interior and Boundary States

We can see from the animation that a Orbital tick can be in one of two states. If prices for all the stablecoins are sufficiently close to the equal $1 price point, then the reserves will be somewhere on the interior tick. But once prices have diverged enough, the tick's reserves will become pinned to its boundary.

Now, imagine we have hundreds or thousands of ticks. Each one of them will either be an "interior tick" or a "boundary tick."

### Consolidation Through Geometry

Locally, all interior ticks behave like spheres. Since they are geometrically similar, we can consolidate them all and treat them like a single sphere.

Similarly, all boundary ticks behave locally like circles (in general, in \(n\) dimensions, they behave like \(n-1\)-spheres).

Logically speaking, we are now dealing with one spherical AMM and one circular AMM. By rotating the sphere around the circle, we obtain a single torus, or donut shape.

The equation of this torus is simple enough that we can compute trades across its surface efficiently onchain. To compute larger trades, we update the equation every time a tick changes from boundary to interior or vice versa.

Luckily, all of this stays true in high-dimensional space, and the rest of the paper goes into the details of how that works.

---

## Mathematical Foundations

### The Sphere AMM Invariant

Orbital is built on top of the Sphere AMM, a generalization of the standard AMM constant product formula \(x \cdot y = k\) to \(n\) assets.

The core invariant is: \(\prod_{i} x_i = k\), where \(x_i\) represents the reserves of asset \(i\).

### Reserve Constraints

To see that the minimum reserve of any asset is always positive, consider the following: as long as asset prices are positive, no-arbitrage implies we should never have reserves of any asset equal to zero. If we did, some trader could remove infinite quantities of that asset without changing the other reserves, which would be an arbitrage opportunity.

### Pricing

Let's say a trader wants to give the AMM some token \(i\) and receive token \(j\).

In this case, we must have:

\[\prod_k x_k' = \prod_k x_k\]

so, abusing notation a bit, we can express the instantaneous price of one unit of \(j\) in terms of \(i\) as:

\[\text{price}_{i \to j} = \frac{x_i'}{x_i} - 1\]

Intuitively we can verify that if the AMM has high reserves of \(i\) relative to \(j\), the price will be lower.

### The Equal Price Point

The most important point on the surface of our AMM is the point where all reserves are equal, so that, by symmetry, all prices are equal.

This should be the the normal state for stablecoins, because under normal conditions they should all worth the value they are pegged to, e.g. $1.

Let's denote this point as \(\vec{c} = (c, c, \ldots, c)\).

By our sphere constraint, we have:

\[c^n = k\]

So then:

\[c = k^{1/n}\]

and we have:

\[\vec{c} = (k^{1/n}, k^{1/n}, \ldots, k^{1/n})\]

Since they're all multiples of the same constant, we can write \(\vec{c} = k^{1/n} \cdot \vec{1}\), where \(\vec{1}\) is the all-ones vector.

In terms of trading, we can think of \(\vec{c}\) as the "natural" price point for stablecoins.

---

## Polar Reserve Decomposition

This section introduces a concept and notation we'll be using to work with ticks through the rest of the paper.

Given any valid reserve state \(\vec{x}\), we can decompose it into a component parallel to \(\vec{1}\) and a component orthogonal to \(\vec{1}\):

\[\vec{x} = \alpha \vec{1} + \vec{x}_\perp\]

where \(\alpha = \frac{\vec{x} \cdot \vec{1}}{|\vec{1}|^2} = \frac{\sum x_i}{n}\), the average reserve.

In other words, for any reserve state \(\vec{x}\), we have:

\[\vec{x} = \frac{\sum x_i}{n} \vec{1} + (\vec{x} - \frac{\sum x_i}{n} \vec{1})\]

Note that because \(\vec{x}_\perp \cdot \vec{1} = 0\), the decomposition is unique.

Viewed through the lens of this decomposition, our AMM constraint becomes:

\[\prod_i (\alpha + x_{\perp,i}) = k\]

Since \(\prod_i \alpha = \alpha^n\), and \(\alpha > 0\), the constraint is equivalent to an inequality constraint on \(\vec{x}_\perp\).

Or, rearranging:

\[\prod_i (1 + x_{\perp,i}/\alpha) = (k/\alpha^n)\]

From this, we can see that if we hold the component of reserves parallel to \(\vec{1}\) (i.e., \(\alpha\)) constant, the constraint only depends on \(\vec{x}_\perp\).

In the interest of simplicity, for the rest of the paper we will act as if each tick has only one liquidity provider. Of course, in practice, we would allow multiple LPs to pool their liquidity into the same tick, just like in Uniswap V3.

---

## Tick Geometry and Structure

### Nested Ticks

As a reminder, ticks in Orbital are nested. Each is centered at the equal price point, and larger ticks fully overlap with smaller ticks. This is in contrast to Uniswap V3, where ticks are fully disjoint.

We can think of a tick geometrically as all the points on the sphere's surface that are within some fixed geodesic distance from the equal-price point.

In the 3D case visualized above, it's possible to intuit that we can construct the boundary of such a tick by slicing the sphere with a plane orthogonal to the vector \(\vec{1}\).

### Tick Boundaries

We formalize this construction for higher dimensions below.

Any plane normal to \(\vec{1}\) has the form:

\[\vec{x} \cdot \vec{1} = \text{const}\]

This is another way of saying that the plane consists precisely of all points whose projection on \(\vec{1}\) equals that constant.

From the polar reserve decomposition section above, we can see that when reserves lie on this boundary, since the component of reserves parallel to \(\vec{1}\) is constant at \(\alpha\), we have fixed \(\alpha\) and the sphere constraint becomes a lower-dimensional sphere in the orthogonal subspace.

By symmetry, every point on this boundary will have an equal geodesic distance from the equal price point.

---

## Tick Sizes: Minimal and Maximal Boundaries

This section is relatively technical and defines the sizes of the smallest and largest ticks that make sense.

### Minimal Tick Boundary

The minimal tick boundary would be the equal price point itself, which we derived above as the point \((k^{1/n}, k^{1/n}, \ldots, k^{1/n})\).

For all \(i\), we have \(x_i = k^{1/n}\).

In that case, \(\alpha = k^{1/n}\).

### Maximal Tick Boundary

The maximal tick's boundary is defined by the plane that lets us achieve the highest possible value of \(\alpha\).

For example, consider:

\[\vec{x} = (2k^{1/n}, k^{1/n}, k^{1/n}, \ldots, k^{1/n})\]

It's still on the sphere because:

\[2k^{1/n} \cdot (k^{1/n})^{n-1} = 2k^{1/n} \cdot k^{(n-1)/n} = 2k\]

and we have \(\alpha = \frac{2k^{1/n} + (n-1)k^{1/n}}{n} = \frac{(n+1)k^{1/n}}{n}\).

To see that this is indeed the maximal tick boundary, note that the reserves of all tokens but one are at their minimum of \(k^{1/n}\), and one token is at maximum. The gradient of the constraint would point in the direction of the single high-reserve token, so if the AMM reduces its \(\alpha\) further, it would violate the constraint.

This section explores how tick boundaries affect the minimum and maximum token reserves a tick can hold, and the implications that has for capital efficiency.

---

## Capital Efficiency and Depeg Protection

### Reserve Bounds Within a Tick

Consider an Orbital tick with a plane constraint of \(\vec{x} \cdot \vec{1} = \alpha\).

Let's derive the minimum possible reserves of any one of the coins, which we'll denote as \(x_i^{\min}\).

Our sphere constraint then becomes:

\[\prod_i x_i = k\]

and our plane invariant becomes:

\[\sum_i x_i = n\alpha\]

so that:

\[x_i + \sum_{j \neq i} x_j = n\alpha\]

Solving the resulting quadratic equation for \(x_i^{\min}\):

\[x_i^{\min} = \alpha - \sqrt{\alpha^2 - k^{1/(n-1)}}\]

In terms of trading, this will usually represent the situation where all coins but one depeg to a low value, causing traders to remove as much of that still-stable coin as they can from the AMM.

However, no matter what traders do, they cannot force the reserves of any token below \(x_i^{\min}\). This means the liquidity provider creating the tick can act as if they have "virtual reserves" of \(x_i^{\min}\) that they don't need to actually hold.

We can repeat the above derivation but flip the sign of the square root to find the *maximum* quantity of any given coin in the tick assuming both constraints are binding.

Since, if prices are positive, no coin balance will go above its maximum in this scenario:

\[x_i^{\max} = \alpha + \sqrt{\alpha^2 - k^{1/(n-1)}}\]

### Single Depeg Events

In terms of trading, this will normally represent the situation where one single coin loses its peg and falls in value, while the other coins remain stable, causing traders to give the AMM as much of that one coin as they can. We call this a single-depeg event.

If we assume that the most common way things will "go wrong" is a single depeg event of the type described in the section immediately above, then for small enough \(\epsilon\), we have:

\[\text{capital efficiency} \approx \frac{1 - \epsilon}{2\epsilon}\]

Assuming only one coin depegs and the rest stay constant, and that \(\epsilon = 0.10\), we get roughly a 4.5x capital efficiency increase.

### Depeg Price Calculation

Recall from the section on pricing that the instantaneous price of token \(i\) in terms of another token \(j\) depends on the ratio of reserves.

In that case, the tick boundary corresponds to the single token depegging to \(\epsilon\) times its original price.

We can then invert this to obtain, for a given depeg price of \(\epsilon\), the required tick boundary.

Note that for large-enough \(\epsilon\) values, the formula gives more dramatic capital efficiency increases.

### Capital Efficiency Gains

As we derived above, given a plane constant \(\alpha\), each LP can store their capital in multiple reserve ratios. For each of the \(n\) coins, we can compute the capital efficiency gain.

So, assuming prices never diverge enough to push reserves past the boundary of the tick, there is a capital efficiency gain of roughly:

\[\text{efficiency} = \frac{1}{1 - \sqrt{1 - (k/\alpha^n)^{1/(n-1)}}}\]

Using the depeg price formula from the prior section, we can compute how much capital efficiency you get by picking a boundary corresponding to a max depeg price of \(p_{\min}\).

For example, in the 5-asset case, a depeg limit of $0.90 corresponds to around a 15x capital efficiency increase, while a limit of $0.99 corresponds to around a 150x capital efficiency increase.

You can view the interactive graph on [Desmos](https://www.desmos.com/calculator) here.

---

## Multi-Tick Trading and Consolidation

### Full Orbital AMM Structure

A full Orbital AMM consists of multiple Orbital ticks with different boundaries and sizes. In this section, we discuss situations in which multiple ticks can be treated as one for the purposes of trade calculations. This will set us up to construct a global trade invariant for the overall orbital AMM in the next section.

As a reminder, for the sake of simplicity we will assume each tick has only a single LP.

### Case 1: Both Interior Ticks

Imagine we have 2 ticks, *A* and *B*.

The simplest case is that both reserves vectors begin and end the trade "interior" to their respective ticks, which is to say, not on the tick boundary -- i.e., \(\vec{x}_A \cdot \vec{1} \neq \alpha_A\) and \(\vec{x}_B \cdot \vec{1} \neq \alpha_B\).

In this case, both ticks behave locally like normal spherical AMMs, and it must be that:

\[\prod_i x_{A,i} = k_A\]
\[\prod_i x_{B,i} = k_B\]

Since by definition, prices must be the same across both ticks to avoid arbitrage:

\[\frac{x_{A,i}}{x_{A,j}} = \frac{x_{B,i}}{x_{B,j}}\]

for all pairs \(i, j\).

This means the combined reserves of the two AMMs are equal to:

\[\prod_i (x_{A,i} + x_{B,i}) = k_A + k_B\]

Since our AMM constant is \(\prod_i x_i = k\), we can treat the two AMMs as a single one with constant \(k_A + k_B\).

### Case 2: Both Boundary Ticks

As soon as one of the reserve vectors hits the boundary of its tick, we can no longer treat the two ticks as a single spherical AMM, and must move on to one of the later cases.

Let's say that both ticks start with reserves that are on their boundaries as defined by their plane constants.

Now imagine that they execute a trade \(\vec{\delta}\):

\[\vec{x}_A' = \vec{x}_A + \delta_A\]
\[\vec{x}_B' = \vec{x}_B + \delta_B\]

where \(\vec{\delta} = \delta_A + \delta_B\).

In this case for tick A:

\[\prod_i x'_{A,i} = k_A\]

This means the trade vector \(\delta_A\) must satisfy the constraint of the sphere in the subspace orthogonal to \(\vec{1}\).

As we discussed in the section on tick boundary geometry, ticks on their boundaries behave like spherical AMMs in the subspace orthogonal to \(\vec{1}\).

---

## Computing Trades: The Global Invariant

This section describes how we can locally compute trades using all of our ticks simultaneously. It is extremely dense. Your favorite LLM may be of some assistance if you are wanting to parse it.

### Consolidation of Interior and Boundary Ticks

First, note that the tick consolidation section above shows we can consolidate all currently interior ticks into a single spherical tick in \(\mathbb{R}^n\).

We call the total reserve vector of our combined Orbital AMM:

\[\vec{x}^{\text{total}} = \vec{x}^{\text{interior}} + \vec{x}^{\text{boundary}}\]

for some constants \(k_{\text{interior}}\) and \(k_{\text{boundary}}\).

We do the same for our consolidated and boundary ticks:

\[\vec{x}^{\text{interior}} = \alpha^{\text{interior}} \vec{1} + \vec{x}^{\text{interior}}_\perp\]
\[\vec{x}^{\text{boundary}} = \alpha^{\text{boundary}} \vec{1} + \vec{x}^{\text{boundary}}_\perp\]

and because \(\vec{x}^{\text{boundary}} \cdot \vec{1} = n\alpha^{\text{boundary}}\):

\[\vec{x}^{\text{boundary}}_\perp \cdot \vec{1} = 0\]

We know that the boundary reserves:

\[\prod_i x^{\text{boundary}}_i = k_{\text{boundary}}\]

by definition, since a boundary AMM always has its reserves on the boundary as defined by its plane constraint.

By the polar reserve decomposition, we also have:

\[\prod_i (1 + x^{\text{boundary}}_{\perp,i}/\alpha^{\text{boundary}}) = (k_{\text{boundary}}/(\alpha^{\text{boundary}})^n)\]

so that:

\[\prod_i x^{\text{boundary}}_{\perp,i} = (k_{\text{boundary}}/(\alpha^{\text{boundary}})^n - 1) \cdot (\alpha^{\text{boundary}})^n\]

Since \(\vec{x}^{\text{boundary}}_\perp \cdot \vec{1} = 0\), the boundary reserves lie in the \((n-1)\)-dimensional subspace orthogonal to \(\vec{1}\).

### Orthonormal Basis Construction

Construct an orthonormal basis \(\vec{e}_1, \ldots, \vec{e}_{n-1}\) for this subspace.

Since this is just a rotation of the axes, our interior tick is still a spherical AMM between all of these new basis vectors, and our boundary tick, being a spherical AMM in the subspace orthogonal to \(\vec{1}\), can be expressed in terms of these basis vectors.

From this, we can see that the interior tick and boundary tick must hold the same value of \(\alpha\).

### The Torus Invariant Formula

Since the \(\vec{x}^{\text{interior}}_\perp\) and \(\vec{x}^{\text{boundary}}_\perp\) components lie in orthogonal subspaces (actually, the interior tick spans all \(n-1\) dimensions while the boundary spans only \(n-2\)), we have:

\[|\vec{x}^{\text{interior}}_\perp|^2 + |\vec{x}^{\text{boundary}}_\perp|^2 = |\vec{x}^{\text{total}}_\perp|^2\]

Recall from the section on tick boundary geometry that:

\[\prod_i x^{\text{interior}}_{\perp,i} = k_{\text{interior}}/(\alpha^{\text{interior}})^n\]

Since, as we showed in the previous subsection:

\[\alpha^{\text{interior}} = \alpha^{\text{boundary}}\]

Substituting in, we then obtain:

\[\prod_i x^{\text{interior}}_{\perp,i} + \prod_i x^{\text{boundary}}_{\perp,i} = k_{\text{total}}\]

Our interior tick's sphere invariant is:

\[\sum_i (x^{\text{interior}}_{\perp,i})^2 = |\vec{x}^{\text{interior}}_\perp|^2 = f(\alpha)\]

by the Pythagorean theorem, this implies:

\[|\vec{x}^{\text{boundary}}_\perp|^2 = |\vec{x}^{\text{total}}_\perp|^2 - f(\alpha)\]

Substituting in our results from the previous sections and simplifying, we then obtain our **full invariant**:

\[\left(\sum_i (x_i^{\text{total}})^2 - f(\alpha)\right)^2 + \left(\prod_i (x_i^{\text{total}} - \bar{x}) - k_{\text{boundary}}\right)^2 = k_{\text{torus}}\]

Note this is equivalent to the formula for a generalized torus, a higher-dimensional extension of the familiar donut shape. Intuitively, this is because we are "adding together" the liquidity from the interior tick, a full sphere, with the liquidity from the boundary tick, a lower-dimensional sphere in a subspace, just the same way as a donut is constructed by centering a sphere over every point on a circle.

### Efficient Computation

We can directly compute this invariant as:

\[\left(\sum_i x_i^2 - f(\alpha)\right)^2 + \left(\prod_i x_i - k_{\text{boundary}}\right)^2 = k_{\text{torus}}\]

Implementations of orbital should keep track of the sums of reserves and squared reserves that appear in that expression.

Since trades of one token for another affect only two of terms in those sums, we can compute the invariant for trades in constant time regardless of the number of dimensions.

---

## Trade Execution and Boundary Crossing

### Computing Individual Trades

Now that we have the global trade invariant, it is straightforward to compute trades.

Let's say a user provides \(\delta_i\) of token \(i\) and wants to receive \(\delta_j\) of token \(j\).

Starting from some valid reserve state \(\vec{x}\), we need to find \(\vec{x}'\) such that:

\[\vec{x}' = \vec{x} + \delta_i \vec{e}_i - \delta_j \vec{e}_j\]

and the new state satisfies our global invariant.

This is a quartic equation in the two unknowns \(\delta_i\) and \(\delta_j\).

### Handling Tick Boundary Crossings

The global trade invariant we derived in the previous section assumes that ticks maintain their status as either "interior" or "boundary."

However, during trades, the system's state can change in a way that causes a previously interior tick's reserves to become pinned at its boundary (or vice versa). In that case, we need to remove the tick from the consolidated boundary (interior) tick, and add it to the consolidated interior (boundary) tick, and then update the torus formula accordingly.

In this section, we'll explain how to detect when these crossings happen and how to handle them by breaking the trades that cause them into segments.

### Geometric Intuition

Imagine we have several ticks of different sizes, each one a sphere intersected by a plane determined by that tick's plane constant. These spheres might be different sizes depending on their respective radii, but we could imagine "zooming in" or "zooming out" on the spheres so that they all appeared to be the same size, perhaps represented by a radius of 1.

If we were to do this, we would see something interesting: all of the ticks that are currently "interior," i.e. all the ticks whose reserves are not precisely on their plane boundary, would appear to have their reserves at exactly the same point on the sphere. Geometrically, we can say this is because the spheres are *similar*. In terms of trading, we can say, as above, that this is because otherwise there would be an arbitrage opportunity between the ticks.

Furthermore, ticks have their reserves trapped on their plane boundary and become boundary ticks precisely when this common reserve point strays farther from the equal price point than that tick's plane boundary.

### Trade Segmentation Algorithm

So, in order to trade across ticks, we just compute the trade assuming no ticks have moved from interior to boundary as described in the section on within-tick trades. Then we check the new common interior reserve point and see if it has crossed over the plane boundary of either the closest interior tick or the closest boundary tick. If it has, we compute the trade exactly up to that boundary point, update the type of the tick that was crossed, and compute the rest of the trade.

We use normalized quantities to compare ticks of different sizes by dividing through by the tick radius.

The *normalized position* is:

\[\hat{x}_i = \frac{x_i - \bar{x}}{r_{\text{tick}}}\]

The *normalized projection* is:

\[\hat{\alpha} = \frac{\alpha - \bar{x}}{r_{\text{tick}}}\]

The *normalized boundary* is:

\[\hat{\alpha}_{\text{boundary}} = \frac{\alpha_{\text{boundary}} - \bar{x}}{r_{\text{tick}}}\]

Note that if \(\hat{\alpha} < \hat{\alpha}_{\text{boundary}}\), the tick is interior. Otherwise, it is boundary.

### Trade Computation Steps

Suppose that for a given tick we have:

\[\hat{x}_i = \hat{\alpha} + \delta_i\]

for small perturbations \(\delta_i\).

This interior normalized reserve vector has a projection:

\[|\hat{\alpha}| < |\hat{\alpha}_{\text{boundary}}|\]

A given tick crosses a boundary when:

\[|\hat{\alpha}_{\text{new}}| = |\hat{\alpha}_{\text{boundary}}|\]

At any given time, the AMM's location in tick space is demarcated by \(\hat{\alpha}\).

### Step-by-Step Trade Algorithm

Let's say we are trying to compute a trade \(\vec{\delta}\).

**Calculate Assuming No Tick Boundary Crossing:** Assume all currently interior ticks stay interior and all currently boundary ticks stay boundary and compute the potential final AMM state.

**Boundary Crossing Check:** If our assumptions were correct and no ticks changed from interior to boundary or vice versa, then we will have:

\[|\hat{\alpha}_{\text{new}}| \leq \max(|\hat{\alpha}_{\text{boundary,interior}}|, |\hat{\alpha}_{\text{boundary,boundary}}|)\]

If that's the case, we're done. Otherwise, we need to segment the trade.

**Segmentation (If Crossing Detected)**

We know the normalized boundary being crossed from the prior step, which we'll call \(\hat{\alpha}_{\text{cross}}\).

So then at the crossover point, we have:

\[|\hat{\alpha}_{\text{cross}}| = |\hat{\alpha}_{\text{boundary}}|\]

where the specific boundary depends on which tick is being crossed.

**Find Intersection Trade**

We want to find the trade \(\vec{\delta}_{\text{segment}}\) such that:

\[\hat{\alpha}_{\text{segment}} = \hat{\alpha}_{\text{cross}}\]

between the current state and the crossing point, so that we see:

\[|\hat{\alpha}_{\text{cross}}| = |\hat{\alpha}_{\text{boundary}}|\]

Substituting that in to the global invariant formula from above yields a quadratic equation in \(\hat{\alpha}\).

Once we find the crossover point, we can execute the trade up to there, adjust the crossed tick from interior to boundary or vice versa, and proceed with the rest of the trade, re-segmenting if necessary.

---

## Conclusion

Today, Orbital is just a design, but we're excited to see how it might change the stablecoin liquidity landscape.

If you're interested in exploring with us, we'd love to hear from you.

---

*Copyright © 2025 Paradigm Operations LP All rights reserved. "Paradigm" is a trademark, and the triangular mobius symbol is a registered trademark of Paradigm Operations LP*