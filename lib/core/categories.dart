const expenseCategories = [
  'Food', 'Travel', 'Shopping', 'Bills', 'Rent',
  'Entertainment', 'Health', 'Education', 'Subscription', 'Other',
];
const incomeCategories = [
  'Salary', 'Freelance', 'Business', 'Investment', 'Gift', 'Other',
];
final allCategories = {...expenseCategories, ...incomeCategories}.toList();