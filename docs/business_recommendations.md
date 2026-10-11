# Business Recommendations Framework

> **Important:** everything in this document is a **hypothesis to test**, not a proven causal effect. Segments
> describe observed customer behaviour. This project does **not** predict churn - the dataset has no churn outcome
> and no predictive model is trained.

The pipeline writes the recommendations for **your run** (with the actual segment statistics as evidence) to:

- `outputs/tables/business_recommendations.csv`
- `outputs/reports/segment_recommendations.md`
- Section 11 of the R Markdown report

The cluster results can change if you use different data or change `CONFIG$k_final`, so the playbook below is keyed by *segment type*, not by cluster number.

## Playbook

| Segment type (assigned from data) | Typical profile | Recommended action | Hypothesis to test | Suggested KPIs |
|---|---|---|---|---|
| **High-Value Customers** | High income, high spending | Loyalty benefits, early access, premium offers | A loyalty tier with premium perks increases repeat visits and basket size | Repeat purchase rate, average basket value, tier enrolment |
| **Potential Loyal Customers** | High spending, lower or average income | Personalised recommendations and budget-appropriate rewards | Personalised offers turn high engagement into long-term loyalty | Repeat purchase rate, offer redemption, share of wallet |
| **Customers Requiring Further Engagement** | High income, low spending | Targeted engagement campaigns, product-fit discovery, feedback surveys | These customers have capacity to spend but are not engaged; relevant offers raise spending | Spending uplift vs. control, response rate, survey feedback |
| **Average Customers** | Mid income and spending | Maintain service quality; test bundles and seasonal promotions | Bundles move part of the middle group to higher spending | Bundle conversion, basket value, promotion ROI |
| **Low-Spending Customers** | Low income, low spending | Low-cost relevant offers; improve engagement without heavy spend | Light-touch, price-appropriate offers lift engagement at acceptable cost | Response rate, cost per engaged customer |

## How to test a recommendation

1. Pick one segment and one action.
2. Randomly split the segment into a treatment group and a control group.
3. Run the campaign for a fixed period and measure the KPIs for both groups.
4. Only conclude that the action worked if the treatment group beats the control group by more than chance would explain.

## Limits of these recommendations

- They are based on three variables (age, income, spending score).
- "Requires further engagement" means low spending relative to income, **not** that a customer is about to leave.
- Spending Score is an index, not revenue; estimate financial impact with real transaction data before committing budget.
